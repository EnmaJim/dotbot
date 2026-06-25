function Invoke-TaskAppendEvidence {
    param([hashtable]$Arguments)
    $taskId = $Arguments['task_id']
    if (-not $taskId) { throw "task_id is required" }
    $body = @{ actor = Get-McpActor }
    foreach ($k in @('label', 'evidence_type', 'note', 'attachments')) {
        if ($Arguments.ContainsKey($k)) { $body[$k] = $Arguments[$k] }
    }
    Invoke-McpRuntimeRequest -Method POST -Path "/tasks/$taskId/evidence" -Body $body
}
