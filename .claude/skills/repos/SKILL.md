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
| `sync` | Check GitHub for updates via `gh` and pull only changed repos |
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

### Sync command

When the user says `/repos sync`, "sync repos", or "update repos from
GitHub", use `gh` to check which repos have new commits on their current
branch and only fetch/pull those. This avoids a slow `fetch --all` across
every repo.

```bash
WORKSPACE_DIR="/workspaces/trl-work"
for repo in "$WORKSPACE_DIR"/*/; do
  [ -d "$repo/.git" ] || continue
  name=$(basename "$repo")
  remote=$(git -C "$repo" remote get-url origin 2>/dev/null)
  # Extract owner/repo from git@github.com:org/repo.git or https URLs
  gh_repo=$(echo "$remote" | sed 's|.*github.com[:/]||;s|\.git$||')
  [ -z "$gh_repo" ] && continue
  branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
  remote_sha=$(gh api "repos/$gh_repo/branches/$branch" --jq '.commit.sha' 2>/dev/null)
  local_sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
  if [ -z "$remote_sha" ]; then
    echo "  $name: could not check (branch $branch not on GitHub?)"
  elif [ "$remote_sha" = "$local_sha" ]; then
    echo "  $name: up to date"
  else
    echo "  $name: syncing $branch..."
    git -C "$repo" fetch origin "$branch" 2>&1
    # Only fast-forward if local is an ancestor of remote
    if git -C "$repo" merge-base --is-ancestor HEAD "origin/$branch" 2>/dev/null; then
      git -C "$repo" pull --ff-only 2>&1
      echo "  $name: updated to ${remote_sha:0:12}"
    else
      echo "  $name: local has diverged — skipping pull (fetch done)"
    fi
  fi
done
```

After running, summarize: how many repos were checked, how many synced,
how many already up to date, and any that diverged or failed.
