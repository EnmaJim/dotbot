# Local Test Procedure

Quick reference for testing dotbot changes end-to-end.

## Prerequisites

- dotbot-v3 repo checked out (source)
- `dotbot-test` sibling directory (disposable test target)
- `c:\temp\spec.txt` containing a project description

## Steps

### 0. Install latest code

```powershell
# From dotbot-v3 repo root
.\install.ps1
```

This copies the current source to `~\dotbot\` so the `dotbot` CLI uses the latest code.

### 1. Clear the test directory

```powershell
Remove-Item -Path '..\dotbot-test\*' -Recurse -Force
```

### 2. Init a fresh project

```powershell
Set-Location '..\dotbot-test'
dotbot init --profile dotnet
```

### 3. Load the spec into clipboard

```powershell
Get-Content c:\temp\spec.txt | Set-Clipboard
```

Paste into the Kickstart modal when prompted.

### 4. Start the UI server

Run in a **separate terminal window** so the current session stays free:

```powershell
Start-Process pwsh.exe -ArgumentList "-NoExit", "-Command", "Set-Location 'C:\Users\andre\repos\dotbot-test'; & '.\.bot\systems\ui\server.ps1'"
```

### 5. Open the browser

Navigate to the URL shown in the server window (default: http://localhost:8686/)

## What to verify

- **Product tab** — shows KICKSTART CTA for new project (or ANALYSE for existing code)
- **Kickstart modal** — description field, file attachment, interview checkbox
- **Processes tab** — kickstart process appears as `running`, transitions to `needs-input`
- **Interview questions** — numbered, each has free-text option, individual submit works
- **Action Required widget** — badge count, slideout renders questions correctly
- **Answer flow** — selecting option + submitting resumes process to next phase
- **Settings tab** — Costs panel present with hourly rate / AI cost fields
- **Roadmap tab** — populated after kickstart completes (if allowed to run fully)
