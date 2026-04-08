# Setup Guide

Manual steps to complete **after** merging the triage workflow files into `main`.

## 1. GitHub Project

Open [https://github.com/users/andresharpe/projects/2](https://github.com/users/andresharpe/projects/2) and configure:

### Status field

Add a single-select **Status** field with these options (in order):

1. Inbox
2. Triage
3. Spec/Design
4. Ready
5. In Progress
6. In Review
7. Done

### Custom fields

Add these fields to the project:

- **PRD link** (text) - URL to the product requirements document
- **Design link** (text) - URL to Figma/design artifact
- **Size** (single-select) - XS, S, M, L, XL
- **Owner** (text or assignee) - who is working on it

### Built-in workflows

Go to Project Settings > Workflows and enable:

- **Auto-add** - any new issue or PR in `andresharpe/dotbot` -> Status = Inbox
- **Item closed** -> Status = Done
- **PR merged** -> Status = Done
- **PR opened linked to issue** -> Status = In Review

### Saved views

Create these saved views:

- **Inbox** - filter: Status = Inbox
- **Triage queue** - filter: label = needs-triage
- **Up for grabs** - filter: Status = Ready, sort by Size
- **In flight** - filter: Status in (In Progress, In Review)

## 2. Repo settings

Go to [https://github.com/andresharpe/dotbot/settings](https://github.com/andresharpe/dotbot/settings):

### Branch protection on `main`

Settings > Branches > Add rule for `main`:

- [x] Require a pull request before merging
- [x] Require approvals: 1
- [x] Dismiss stale pull request approvals when new commits are pushed
- [x] Require status checks to pass before merging
  - Add: `PR link check / check` (the job name from the `pr-link-check` workflow)
- [ ] Do not require branches to be up to date (optional, your call)

### General

- [x] Automatically delete head branches

### Discussions (optional)

Settings > General > Features > [x] Discussions

## 3. Discord webhooks

Provision webhooks using the existing discord.js tooling.

### Run the webhook script

The webhook provisioning scripts live in `ideas/team/discord-setup/` which is gitignored (local tooling only). If you don't have it, ask Andre for a copy.

```bash
cd ideas/team/discord-setup
npm install        # if not already done
npm run webhooks   # runs create-webhooks.js
```

Requires the `DISCORD_BOT_TOKEN` environment variable. Set it via KeePassXC before running (the token is stored under `APIs/discord/dotbot-bot` in the team KeePass vault).

The script will print four webhook URLs. Copy each into the matching GitHub Actions secret:

Go to [Repo Settings > Secrets and variables > Actions](https://github.com/andresharpe/dotbot/settings/secrets/actions) and add:

| GitHub secret | Source channel | Webhook name |
|---|---|---|
| `DISCORD_DEVOPS_WEBHOOK` | #devops | GitHub - New Issues |
| `DISCORD_ADVISORY_WEBHOOK` | #advisory-steering | GitHub - Triage & Stale |
| `DISCORD_CONTRIBUTORS_WEBHOOK` | #ap-contributors | GitHub - Ready for Pickup |
| `DISCORD_PR_WEBHOOK` | #pull-requests | GitHub - PR Activity |

The script is idempotent - re-running reuses existing webhooks with matching names.

## 4. First-run checklist

After completing steps 1-3, verify everything works:

- [ ] Run `npm run webhooks` in `ideas/team/discord-setup/` and add the four secrets to GitHub
- [ ] Run the `sync-labels` workflow manually (Actions > Sync labels > Run workflow) to create all labels
- [ ] File one test issue per template (feature, bug, question) to verify:
  - Auto-labels (`needs-triage`, `type:*`) are applied
  - Project auto-add puts it in Inbox
  - A notification appears in `#devops`
- [ ] Manually add the `ready` label to one test issue:
  - Expect a notification in `#ap-contributors`
- [ ] Open a draft PR with `Closes #<test-issue>` in the body:
  - Expect a notification in `#pull-requests`
  - Expect the project card to move to In Review
- [ ] Trigger `triage-nudge.yml` via workflow_dispatch:
  - Expect a post in `#advisory-steering` (if any `needs-triage` issues exist > 2 days)
- [ ] Add senior contributor GitHub handles to `.github/CODEOWNERS`
- [ ] Verify the Discord invite URLs in `.github/ISSUE_TEMPLATE/config.yml` and `.github/ISSUE_TEMPLATE/question.yml` are still valid (`https://discord.gg/UPQDpN2f8N`)
- [ ] Close/delete the test issues
