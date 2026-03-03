# dotbot-v3

**Structured, auditable AI-assisted development for teams.**

![Overview](assets/overview.png)

## What is dotbot?

Most AI coding tools give you a result but no record of how you got there — no trail of decisions for teammates to follow, no way to continue work across sessions, and no framework for managing large projects.

dotbot wraps AI-assisted coding in a managed, transparent workflow where every step is tracked:

- **Plan first, then execute** — Product specs become task roadmaps. Each task gets pre-flight analysis before implementation. Decisions and rationale are documented as work happens.
- **Two-phase execution** — Analysis resolves ambiguity, identifies files, and builds a context package. Implementation consumes that package and writes code. Tasks flow: `todo → analysing → analysed → in-progress → done`.
- **Per-task git worktree isolation** — Each task runs in its own worktree on an isolated branch, squash-merged back to main on completion.
- **Full audit trail** — Every AI session, question, answer, and code change is recorded in version-controlled JSON. Your team can review exactly what happened, when, and why.
- **Multi-provider** — Switch between **Claude**, **Codex**, and **Gemini** from the Settings tab. Each provider has its own CLI wrapper, stream parser, and model configuration.
- **Operator steering** — Guide the AI mid-session through a heartbeat/whisper system. `/status` and `/verify` slash commands work during autonomous execution.
- **Kickstart interview** — Guided requirements-gathering flow that produces product documents (mission, tech stack, entity model), then generates a task roadmap automatically.
- **Human-in-the-loop Q&A** — When a task needs human input, dotbot routes multi-choice questions to stakeholders via **Teams**, **Email**, or **Jira** using Adaptive Cards. The DotbotServer (see `server/`) is a .NET 9 Teams bot that delivers questions, collects answers, and feeds decisions back into the workflow.
- **Feedback loop** — Structured problem logs capture issues encountered during execution, with root-cause analysis and prevention suggestions that feed back into future runs.
- **Zero-dependency tooling** — MCP server and web UI are pure PowerShell. No npm, pip, or Docker required.
- **Designed for teams** — The entire `.bot/` directory lives in your repo. Task queues, session histories, plans, and feedback are visible to everyone through git.
- **Fully extensible** — Hooks, verification scripts, agents, skills, and workflows can all be customised per-project.
- **Profile system** — **Workflow** profiles (e.g. `multi-repo`) change how dotbot operates. **Stack** profiles (e.g. `dotnet`, `dotnet-blazor`) add tech-specific skills, hooks, and tools. Stacks can extend other stacks and compose additively.
- **Security** — PathSanitizer strips absolute paths from AI output, privacy scan covers the full repo, and pre-commit hooks run gitleaks on staged files.

## Prerequisites

**Required:**
- **PowerShell 7+** — [Download](https://aka.ms/powershell)
- **Git** — [Download](https://git-scm.com/downloads)
- **AI CLI** (at least one) — [Claude CLI](https://docs.anthropic.com/en/docs/claude-cli), [Codex CLI](https://github.com/openai/codex), or [Gemini CLI](https://github.com/google-gemini/gemini-cli)

**Recommended MCP servers:**
- **[Playwright MCP](https://github.com/anthropics/anthropic-quickstarts/tree/main/mcp-playwright)** — Browser automation for UI testing and verification.
- **[Context7 MCP](https://github.com/upstash/context7)** — Library documentation lookup to reduce hallucination.

> **Windows ZIP download?** Run this first:
> ```powershell
> Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

## Quick Start

### 1. Install dotbot globally (one-time)

```powershell
cd ~
git clone https://github.com/andresharpe/dotbot-v3 dotbot-install
cd dotbot-install
pwsh install.ps1
```

Restart your terminal so the `dotbot` command is available.

### 2. Add dotbot to your project

```powershell
cd your-project
dotbot init
```

This creates a `.bot/` directory with the MCP server, web UI, autonomous runtime, agents, skills, and workflows.

#### Profiles

```powershell
dotbot init --profile dotnet                          # Single stack
dotbot init --profile multi-repo,dotnet-blazor,dotnet-ef  # Workflow + stacks
dotbot profiles                                       # List available profiles
```

- **Workflow** (at most one) — Changes how dotbot operates. Example: `multi-repo` adds a research-driven multi-repo pipeline with Atlassian and Azure DevOps integration.
- **Stack** (composable) — Adds tech-specific skills, hooks, verify scripts, and MCP tools. Stacks can declare `extends` to auto-include a parent (e.g. `dotnet-blazor` extends `dotnet`).

Apply order: `default` → workflow (if any) → stacks (dependency-resolved). Settings are deep-merged; files are overlaid.

### 3. Configure MCP Server

Add to your AI tool's MCP settings (Claude, Warp, etc.):

```json
{
  "mcpServers": {
    "dotbot": {
      "command": "pwsh",
      "args": ["-NoProfile", "-File", ".bot/systems/mcp/dotbot-mcp.ps1"]
    }
  }
}
```

### 4. Start the UI

```powershell
.bot\go.ps1
```

Opens the web dashboard (default port 8686, auto-selects next available if busy).

## Screenshots

![Overview](assets/overview.png)
![Product](assets/product.png)
![Workflow](assets/workflow.png)
![Settings](assets/settings.png)

## Commands

```powershell
dotbot help          # Show all commands
dotbot init          # Add dotbot to current project
dotbot init -Force   # Reinitialize (preserves workspace data)
dotbot init --profile dotnet                          # With a stack profile
dotbot init --profile multi-repo,dotnet-blazor        # Workflow + stacks
dotbot profiles      # List available profiles
dotbot status        # Check installation status
dotbot update        # Update global installation
```

## Architecture

```
.bot/
├── systems/            # Core systems
│   ├── mcp/            # MCP server (stdio, auto-discovers tools)
│   │   ├── tools/      # One folder per tool (metadata.yaml + script.ps1)
│   │   └── modules/    # NotificationClient, PathSanitizer, SessionTracking
│   ├── ui/             # Pure PowerShell HTTP server + vanilla JS frontend
│   └── runtime/        # Autonomous loop, worktree manager, provider CLIs
│       └── ProviderCLI/  # Stream parsers for Claude, Codex, Gemini
├── defaults/           # Default settings + provider configurations
├── prompts/            # AI prompts
│   ├── agents/         # Specialized personas (implementer, planner, reviewer, tester)
│   ├── skills/         # Reusable capabilities (unit tests, status, verify)
│   └── workflows/      # Numbered step-by-step processes
├── workspace/          # Version-controlled runtime state
│   ├── tasks/          # Task queue (todo/analysing/analysed/in-progress/done/…)
│   ├── sessions/       # Session history + run logs
│   ├── product/        # Product docs (mission, tech stack, entity model)
│   ├── plans/          # Execution plans
│   ├── feedback/       # Structured problem logs (pending/applied/archived)
│   └── reports/        # Generated reports
├── hooks/              # Project-specific scripts (dev, verify, steering)
├── init.ps1            # IDE integration setup
└── go.ps1              # Launch UI server
```

## MCP Tools

The dotbot MCP server exposes 26 tools, auto-discovered from `systems/mcp/tools/`:

**Task Management**: `task_create`, `task_create_bulk`, `task_get_next`, `task_get_context`, `task_list`, `task_get_stats`, `task_mark_todo`, `task_mark_analysing`, `task_mark_analysed`, `task_mark_in_progress`, `task_mark_done`, `task_mark_needs_input`, `task_mark_skipped`, `task_answer_question`, `task_approve_split`

**Session Management**: `session_initialize`, `session_get_state`, `session_get_stats`, `session_update`, `session_increment_completed`

**Plans**: `plan_create`, `plan_get`, `plan_update`

**Steering**: `steering_heartbeat`

**Development**: `dev_start`, `dev_stop`

Stack and workflow profiles can add their own tools (e.g. `multi-repo` adds `repo_clone`, `repo_list`, `atlassian_download`, `research_status`).

See `.bot/README.md` for full tool documentation.

## Testing

```powershell
pwsh tests/Run-Tests.ps1            # Run layers 1-3
pwsh tests/Run-Tests.ps1 -Layer 1   # Structure tests
pwsh tests/Run-Tests.ps1 -Layer 2   # Component tests
pwsh tests/Run-Tests.ps1 -Layer 3   # Mock provider tests
pwsh tests/Run-Tests.ps1 -Layer 4   # E2E (requires API key)
```

CI runs layers 1–3 on every push and PR across Windows, macOS, and Linux. Layer 4 runs on schedule or manual trigger.

## Troubleshooting

**`dotbot` command not found after install** — Restart your terminal. The installer adds `~/dotbot/bin` to your PATH.

**Script execution blocked on Windows** — Run `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` and try again.

**PowerShell version error** — Requires PowerShell 7+. Check with `$PSVersionTable.PSVersion` and [upgrade](https://aka.ms/powershell) if needed.

## License

MIT
