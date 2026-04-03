---
name: repos
description: Run repos.sh workspace repository management commands (status, update, report, health, log, changelog, etc.)
user-invocable: true
---

# Workspace Repository Management

Use the `repos.sh` tool to manage workspace git repositories.

## Instructions

Derive the tool path from the `Base directory` shown in the skill invocation header
(`Base directory for this skill: <base-dir>`):

- Tool: `<base-dir>/../../../tools/repos.sh`
- Working directory: `<base-dir>/../../..` (parent of `.devcontainer`)

For example, given `Base directory: /home/gabe/Work/.devcontainer/.claude/skills/repo`:
- Tool: `/home/gabe/Work/.devcontainer/tools/repos.sh`
- Working directory: `/home/gabe/Work`

Always set `WORKSPACE_DIR` to the workspace directory when invoking the tool:

```bash
WORKSPACE_DIR=<workspace-dir> <tool-path> <command>
```

Run the appropriate command based on the user's request.

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
| `changelog` | Commits in a date range: `repos.sh changelog YYYY-MM-DD YYYY-MM-DD` |
| `outdated` | Show repos behind their upstream |
| `health` | Comprehensive health check |
| `exec` | Run arbitrary git command across repos: `repos.sh exec <git-args>` |
| `report` | Table of repos needing attention with reasons and fixes |
| `help` | Show help |

### Single-repo mode

Target one repo with `--single <repo>-<command>`:

```bash
<tool-path> --single trl-viponly-status
```

### Default behavior

If the user says `/repos` with no arguments, run `report` to show the
workspace overview table. Otherwise, match their intent to the closest
command above.

Present the output directly to the user. For `update` and `report`, add a
brief summary after the output (counts of updated/skipped/failed or repos
needing attention).
