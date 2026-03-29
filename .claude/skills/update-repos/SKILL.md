---
name: update-repos
description: Fetch and pull all workspace repositories that can be safely updated without losing uncommitted work, then report status
user-invokable: true
allowed-tools: Bash, Read
---

# Update Workspace Repositories

Safely update all git repositories in the workspace by fetching and pulling where possible.

## Instructions

Run the update script:

!`/workspaces/trl-work/.claude/skills/update-repos/update-repos.sh`

Read the script output and present a summary to the user:

1. **Updated** — repos that were successfully pulled
2. **Skipped** — show a table with columns: Repo, Branch, Reason, How to Resolve. Include the branch name (or "detached" / "unknown" if applicable), the skip reason from the script output, and a brief resolution (e.g., stash or commit changes, checkout a branch, set upstream tracking).
3. **Failed** — repos where fetch or pull failed unexpectedly
