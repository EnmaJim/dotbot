<#
.SYNOPSIS
File system listener that triggers task-creation when new files appear in configured workspace folders.

.DESCRIPTION
Monitors folders defined in settings.default.json under file_listener.watchers.
When a matching file is created or updated, launches a task-creation process
(91-new-tasks.md) with the file path as context so Claude can review the new
document against existing tasks and product docs and create appropriate tasks.

Architecture note: Each watcher runs its own dedicated worker runspace that owns
the FileSystemWatcher and calls WaitForChanged() in a loop. This avoids Register-ObjectEvent
entirely — no PS event system, no $script: scope issues, no silent failures.
#>

# Module-scope state
$script:WorkerPSList = [System.Collections.Generic.List[powershell]]::new()
$script:BotRoot      = $null

function Initialize-InboxWatcher {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BotRoot
    )

    $script:BotRoot = $BotRoot
    $workspaceRoot  = Join-Path $BotRoot "workspace"

    # Read file_listener config from settings
    $settingsPath = Join-Path $BotRoot "settings\settings.default.json"
    if (-not (Test-Path $settingsPath)) {
        Write-BotLog -Level Debug -Message "[InboxWatcher] settings.default.json not found at $settingsPath, skipping"
        return
    }

    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    } catch {
        Write-BotLog -Level Warn -Message "[InboxWatcher] Failed to parse settings.default.json" -Exception $_
        return
    }

    $listenerConfig = $settings.file_listener
    if (-not $listenerConfig -or $listenerConfig.enabled -ne $true) {
        Write-BotLog -Level Debug -Message "[InboxWatcher] File listener disabled or not configured"
        return
    }

    $watcherDefs = @($listenerConfig.watchers)
    if ($watcherDefs.Count -eq 0) {
        Write-BotLog -Level Debug -Message "[InboxWatcher] No watchers configured"
        return
    }

    $logPath = Join-Path $BotRoot ".control\logs\inbox-watcher.log"

    foreach ($watcherDef in $watcherDefs) {
        $folder = $watcherDef.folder
        if (-not $folder) {
            Write-BotLog -Level Warn -Message "[InboxWatcher] Watcher config missing 'folder' field, skipping"
            continue
        }

        $resolvedPath = Join-Path $workspaceRoot $folder
        if (-not (Test-Path $resolvedPath)) {
            Write-BotLog -Level Warn -Message "[InboxWatcher] Watched folder not found, skipping: $resolvedPath"
            continue
        }

        $filter      = if ($watcherDef.filter)      { $watcherDef.filter }      else { '*' }
        $events      = if ($watcherDef.events)      { @($watcherDef.events) }   else { @('created') }
        $folderLabel = if ($watcherDef.description) { $watcherDef.description } else { "watched folder ($folder)" }

        $watchCreated = 'created' -in $events
        $watchUpdated = 'updated' -in $events

        if (-not $watchCreated -and -not $watchUpdated) {
            Write-BotLog -Level Warn -Message "[InboxWatcher] No valid events configured for $folder, skipping"
            continue
        }

        # Each watcher gets its own runspace that owns the FileSystemWatcher and
        # calls WaitForChanged() — pure .NET, no Register-ObjectEvent, no scope issues.
        $workerRunspace = [runspacefactory]::CreateRunspace()
        $workerRunspace.Open()
        $workerRunspace.SessionStateProxy.SetVariable('WatchedPath',  $resolvedPath)
        $workerRunspace.SessionStateProxy.SetVariable('Filter',       $filter)
        $workerRunspace.SessionStateProxy.SetVariable('WatchCreated', $watchCreated)
        $workerRunspace.SessionStateProxy.SetVariable('WatchUpdated', $watchUpdated)
        $workerRunspace.SessionStateProxy.SetVariable('FolderLabel',  $folderLabel)
        $workerRunspace.SessionStateProxy.SetVariable('BotRoot',      $script:BotRoot)
        $workerRunspace.SessionStateProxy.SetVariable('LogPath',      $logPath)

        $ps = [powershell]::Create()
        $ps.Runspace = $workerRunspace
        $null = $ps.AddScript({
            function Write-WorkerLog {
                param([string]$Message)
                try {
                    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [InboxWatcher] $Message"
                    Add-Content -Path $LogPath -Value $line -ErrorAction SilentlyContinue
                } catch {}
            }

            Write-WorkerLog "Worker started. Watching: $WatchedPath (filter: $Filter)"

            $watcher = New-Object System.IO.FileSystemWatcher
            $watcher.Path                  = $WatchedPath
            $watcher.Filter                = $Filter
            $watcher.NotifyFilter          = [System.IO.NotifyFilters]::LastWrite -bor
                                             [System.IO.NotifyFilters]::FileName  -bor
                                             [System.IO.NotifyFilters]::CreationTime
            $watcher.InternalBufferSize    = 65536
            $watcher.IncludeSubdirectories = $false
            $watcher.EnableRaisingEvents   = $true

            $watchTypes = [System.IO.WatcherChangeTypes]::None
            if ($WatchCreated) { $watchTypes = $watchTypes -bor [System.IO.WatcherChangeTypes]::Created }
            if ($WatchUpdated) { $watchTypes = $watchTypes -bor [System.IO.WatcherChangeTypes]::Changed }

            $recentlyProcessed = @{}

            while ($true) {
                try {
                    $result = $watcher.WaitForChanged($watchTypes, 2000)
                    if ($result.TimedOut) { continue }

                    $filePath = Join-Path $WatchedPath $result.Name
                    Write-WorkerLog "File detected: $filePath"

                    # Skip directories
                    if (Test-Path $filePath -PathType Container) {
                        Write-WorkerLog "Skipping directory: $filePath"
                        continue
                    }

                    # Debounce: skip if same file processed within last 5 seconds
                    $now = [DateTime]::UtcNow
                    if ($recentlyProcessed.ContainsKey($filePath)) {
                        if (($now - $recentlyProcessed[$filePath]).TotalSeconds -lt 5) {
                            Write-WorkerLog "Debounced: $filePath"
                            continue
                        }
                    }
                    $recentlyProcessed[$filePath] = $now

                    # Purge stale debounce entries (older than 60s)
                    $stale = @($recentlyProcessed.Keys | Where-Object {
                        ($now - $recentlyProcessed[$_]).TotalSeconds -gt 60
                    })
                    foreach ($key in $stale) { $recentlyProcessed.Remove($key) }

                    # Build context prompt
                    $fileName      = Split-Path $filePath -Leaf
                    $contextPrompt = "A new file '$fileName' has been added to $FolderLabel (path: $filePath). Read this file using your available tools, review its contents against the existing product documentation and task list, and create any new tasks needed to address the changes, requirements, or decisions it represents."
                    $description   = "Review new file: $fileName"

                    # Locate launcher
                    $launcherPath = Join-Path $BotRoot "systems\runtime\launch-process.ps1"
                    if (-not (Test-Path $launcherPath)) {
                        Write-WorkerLog "ERROR: Launcher not found at $launcherPath"
                        continue
                    }

                    $escapedPrompt = $contextPrompt -replace '"', '\"'
                    $escapedDesc   = $description   -replace '"', '\"'
                    $launchArgs    = @(
                        "-File", "`"$launcherPath`"",
                        "-Type", "task-creation",
                        "-Prompt", "`"$escapedPrompt`"",
                        "-Description", "`"$escapedDesc`""
                    )

                    $startParams = @{ ArgumentList = $launchArgs }
                    if ($IsWindows) { $startParams.WindowStyle = 'Normal' }

                    Write-WorkerLog "Launching task-creation for: $fileName"
                    Start-Process pwsh @startParams
                    Write-WorkerLog "Launched successfully for: $fileName"
                } catch {
                    Write-WorkerLog "ERROR: $_"
                }
            }
        })
        $null = $ps.BeginInvoke()
        $script:WorkerPSList.Add($ps)
        Write-BotLog -Level Info -Message "[InboxWatcher] Worker started for: $resolvedPath (filter: $filter, events: $($events -join ', '))"
    }

    if ($script:WorkerPSList.Count -gt 0) {
        Write-BotLog -Level Info -Message "[InboxWatcher] Initialization complete. $($script:WorkerPSList.Count) watcher(s) active. Log: $logPath"
    }
}


function Stop-InboxWatcher {
    Write-BotLog -Level Debug -Message "[InboxWatcher] Stopping all inbox watchers"

    foreach ($ps in $script:WorkerPSList) {
        try {
            $ps.Stop()
            $ps.Runspace.Close()
            $ps.Dispose()
        } catch {}
    }
    $script:WorkerPSList.Clear()

    Write-BotLog -Level Debug -Message "[InboxWatcher] All inbox watchers stopped"
}

Export-ModuleMember -Function @(
    'Initialize-InboxWatcher',
    'Stop-InboxWatcher'
)
