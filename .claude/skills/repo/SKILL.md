---
name: repo
description: Run repo.sh workspace repository management commands (status, update, report, health, log, changelog, etc.)
user-invokable: true
allowed-tools: Bash, Read
---

# Workspace Repository Management

Use the `repo.sh` tool to manage workspace git repositories.

## Instructions

The tool is at `/workspaces/trl-work/tools/repo.sh`. Run the appropriate
command based on the user's request.

### Available commands

| Command | Description |
|---------|-------------|
| `list` | List repositories with branch and remote info |
| `status` | Show git status summary for all repos |
| `unpushed` | Check for unpushed commits, untracked branches, stashes |
| `branches` | Show branches (`ALL=1` for remotes too) |
| `fetch` | Fetch all remotes (`PRUNE=1` to prune stale branches) |
| `update` | Fetch and fast-forward all clean repos (safe pull) |
| `log` | Recent commits (`COUNT=N` to change from default 3) |
| `changelog` | Commits in a date range: `repo.sh changelog YYYY-MM-DD YYYY-MM-DD` |
| `outdated` | Show repos behind their upstream |
| `health` | Comprehensive health check |
| `exec` | Run arbitrary git command across repos: `repo.sh exec <git-args>` |
| `report` | Table of repos needing attention with reasons and fixes |
| `help` | Show help |

### Single-repo mode

Target one repo with `--single <repo>-<command>`:

```bash
/workspaces/trl-work/tools/repo.sh --single trl-viponly-status
```

### Default behavior

If the user says `/repo` with no arguments, run `report` to show the
workspace overview table. Otherwise, match their intent to the closest
command above.

Present the output directly to the user. For `update` and `report`, add a
brief summary after the output (counts of updated/skipped/failed or repos
needing attention).
