---
name: team-report
description: >
  Generate an SW team activity report covering git commits, ClickUp tasks,
  Google Drive edits, and Slack messages for Gabe, Said, and Jackson.
  Outputs a markdown file to reports/. Use this skill when the user asks
  for a team report, team summary, team activity, SW team status, or says
  things like "what did the team do today", "team report for last week",
  "SW activity summary", or "generate team report".
user-invokable: true
allowed-tools: Bash, Read, Write, Agent
---

# SW Team Activity Report

Gather activity signals from git, ClickUp, Google Drive, and Slack for
the SW team (Gabe, Said, Jackson), then produce a summary report written
to `reports/`.

All ClickUp operations use the `clickup` CLI with `--format json`.
Parse JSON with `jq` or Python.

## Team Members

| Name | Role |
|------|------|
| Gabe | SW Lead |
| Said | SW Engineer |
| Jackson | SW Engineer |

ClickUp user IDs and Slack user IDs are resolved at runtime (see
CLI Reference). Do not hardcode IDs — resolve them each time.

## Date Range

Parse the caller's request to determine the date range:

| Input | Range |
|-------|-------|
| _(none / "today")_ | Start of today through now |
| `yesterday` | Yesterday 00:00 – 23:59 |
| `last week` / `this week` | Monday through Friday (or Sunday) of the target week |
| `YYYY-MM-DD` to `YYYY-MM-DD` | Exact range |
| `March`, `last month` | Full calendar month |

If the range spans more than one day, label the report as a
**Weekly Activity Report** or **Activity Report (date – date)**.
A single-day range is a **Daily Activity Report**.

## Output

```
reports/team-report-YYYY-MM-DD.md
```

Use the end date of the range in the filename. Create `reports/` if it
does not exist. Overwrite if a file for the same date already exists.

---

## CLI Reference

### ClickUp

```bash
# Resolve all workspace members (get user IDs)
clickup workspace members --format json
```

Match members by first name (case-insensitive contains) to find each
team member's `user.id`. If a name is ambiguous, match on full name or
username.

```bash
# Tasks updated in range, assigned to a user
# NOTE: --date-updated-gt and --date-done-gt do NOT exist in the CLI.
# Instead, fetch tasks ordered by updated (reverse) and filter client-side
# by comparing date_updated (Unix ms) to the start-of-range timestamp.
START_MS=$(date -d "<start_date> 00:00:00" +%s)000
clickup task search \
  --assignee <user_id> \
  --order-by updated \
  --reverse \
  --format json
# Then filter: keep tasks where int(date_updated) >= START_MS

# Closed tasks — same approach, filter date_done client-side
clickup task search \
  --assignee <user_id> \
  --include-closed \
  --order-by updated \
  --reverse \
  --format json
# Then filter: keep tasks where int(date_done) >= START_MS

# Time entries for a user in range
clickup time list \
  --start "<start_date>" \
  --end "<end_date>" \
  --assignee <user_id> \
  --format json
```

For each task, capture: `custom_id`, `name`, `status`, `url`
(`https://app.clickup.com/t/<task_id>`), and `date_updated` /
`date_done`.

### Google Workspace (gws)

Always append `2>/dev/null` when piping to `jq` or Python.

```bash
# Drive files modified in range (visible to the authenticated user)
gws drive files list \
  --params '{
    "q":"modifiedTime > '\''"<start_date>T00:00:00"'\'' and modifiedTime < '\''"<end_date>T23:59:59"'\''",
    "orderBy":"modifiedTime desc",
    "fields":"files(id,name,webViewLink,modifiedTime,mimeType,lastModifyingUser)",
    "pageSize":50
  }' \
  --format json 2>/dev/null
```

Filter results client-side by `lastModifyingUser.displayName` matching
team member names. Capture `name`, `webViewLink`, `modifiedTime`, and
who modified it.

### Slack (via curl)

**Token:** Use the Team Reports user token stored at
`~/.slack/team-reports-token`. This token has `channels:history`,
`groups:history`, and `search:read` scopes.

```bash
# Load token (prefer team-reports token, fall back to CLI token)
SLACK_TOKEN="${SLACK_TOKEN:-$(cat "$HOME/.slack/team-reports-token" 2>/dev/null)}"
if [ -z "$SLACK_TOKEN" ]; then
  SLACK_TOKEN=$(python3 -c "
import json
with open('$HOME/.slack/credentials.json') as f:
    creds = json.load(f)
for ws in creds.values():
    print(ws.get('token', '')); break
" 2>/dev/null)
fi
```

**Preferred method: `search.messages`** — searches across all channels
at once, no per-channel scanning needed.

```bash
# Search for messages from a team member in a date range
# Date filter format: after:YYYY-MM-DD before:YYYY-MM-DD
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  --data-urlencode "query=from:<username> after:<start_date> before:<end_date_plus_one>" \
  "https://slack.com/api/search.messages?count=100" | jq .
```

Results are in `.messages.matches[]`. Each match contains:
- `text` — message text
- `channel.name` — channel name
- `permalink` — direct link to the message
- `ts` — timestamp
- `username` — author

Run one search per team member:
```bash
# Search for each team member
for user in gabe said jackson; do
  curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
    --data-urlencode "query=from:$user after:<start_date> before:<end_date_plus_one>" \
    "https://slack.com/api/search.messages?count=100"
done
```

Paginate with `&page=2`, `&page=3`, etc. if `paging.pages > 1`.

**Fallback: `conversations.history`** — use only if `search.messages`
fails (e.g. missing `search:read` scope).

```bash
# Read messages from a specific channel in the date range
START_TS=$(date -d "<start_date> 00:00:00" +%s)
END_TS=$(date -d "<end_date> 23:59:59" +%s)
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/conversations.history?channel=<channel_id>&oldest=$START_TS&latest=$END_TS&limit=200"
```

If the token is missing or API calls fail, skip Slack silently and
note it in the report footer.

### Git

Sync repos that have remote changes, then scan for commits:

```bash
# Sync repos with remote changes first
for repo in /workspaces/trl-work/*/; do
  [ -d "$repo/.git" ] || continue
  remote=$(git -C "$repo" remote get-url origin 2>/dev/null)
  gh_repo=$(echo "$remote" | sed 's|.*github.com[:/]||;s|\.git$||')
  branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
  remote_sha=$(gh api "repos/$gh_repo/branches/$branch" --jq '.commit.sha' 2>/dev/null)
  local_sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
  if [ -n "$remote_sha" ] && [ "$remote_sha" != "$local_sha" ]; then
    git -C "$repo" fetch origin "$branch" 2>&1
    git -C "$repo" merge-base --is-ancestor HEAD "origin/$branch" 2>/dev/null && \
      git -C "$repo" pull --ff-only 2>&1
  fi
done

# Collect commits from all team members
for repo in /workspaces/trl-work/*/; do
  [ -d "$repo/.git" ] || continue
  commits=$(git -C "$repo" log --oneline \
    --after="<start_date>T00:00:00" \
    --before="<end_date_plus_one>T00:00:00" \
    --author="gabe\|Gabe\|said\|Said\|jackson\|Jackson" \
    --format="%h|%an|%ad|%s" --date=short 2>/dev/null)
  if [ -n "$commits" ]; then
    echo "=== $(basename "$repo") ==="
    echo "$commits"
  fi
done
```

For each commit, capture: repo name, short hash, author, date, subject.

---

## Workflow

### Step 1 — Determine date range

Parse the user's request. Default to today. Convert relative terms
to absolute dates. Store `START_DATE`, `END_DATE`, and
`END_DATE_PLUS_ONE` (day after end, for git `--before`).

### Step 2 — Resolve team member IDs

```bash
clickup workspace members --format json
```

Find ClickUp user IDs for Gabe, Said, and Jackson by matching on
first name. Store as a map: `{name: clickup_user_id}`.

### Step 3 — Gather activity (parallelize where possible)

Collect data from all four sources for all three team members.
Use the Agent tool to parallelize independent data gathering where
it helps.

**3a. Git commits** — Sync repos, then scan for commits by all three
authors in the date range. Group by repo, then by author.

**3b. ClickUp tasks** — For each team member:
- Search tasks ordered by updated (reverse), filter client-side by `date_updated >= start_ms`
- Search closed tasks (`--include-closed`), filter client-side by `date_done >= start_ms`
- Fetch time entries in the range

Deduplicate tasks that appear in both searches. For each task, note
the member, task ID, name, status, and URL.

**3c. Google Drive** — Search for files modified in the date range.
Filter by `lastModifyingUser` matching team member names. Note: this
only shows files visible to the authenticated Google account.

**3d. Slack** — List channels, pull messages in range, filter for
team member authors. Group by channel, note author and message
summary.

### Step 4 — Build the report

Structure the report as follows:

```markdown
# SW Team Activity Report
_<Report type> — <date range display> | Generated: <today>_

## Summary
<2-4 sentence narrative overview of the team's main activities>

---

## Gabe
### Git Activity
| Repo | Commits | Highlights |
|------|---------|------------|
...

### ClickUp Tasks
| Ticket | Task | Status | Action |
|--------|------|--------|--------|
| [SW-XXXX](url) | Task name | status | Updated / Closed / In Progress |
...

### Google Drive
| File | Modified |
|------|----------|
| [Filename](webViewLink) | timestamp |
...

### Slack
| Channel | Messages | Topics |
|---------|----------|--------|
| #channel | N msgs | brief topic summary |
...

---

## Said
_(same structure as above)_

---

## Jackson
_(same structure as above)_

---

## Cross-Team Activity

### Shared Tickets
<Tasks where multiple team members appear as assignees or had activity>

### Collaboration Signals
<Slack threads with multiple team members, shared doc edits, related commits>

---

## Metrics

| Member | Commits | Tasks Updated | Tasks Closed | Hours Logged | Drive Edits | Slack Messages |
|--------|---------|---------------|--------------|--------------|-------------|----------------|
| Gabe   | N       | N             | N            | N.Nh         | N           | N              |
| Said   | N       | N             | N            | N.Nh         | N           | N              |
| Jackson| N       | N             | N            | N.Nh         | N           | N              |
| **Total** | **N** | **N**        | **N**        | **N.Nh**     | **N**       | **N**          |

---

_Sources: Git (local repos), ClickUp, Google Drive, Slack_
_<Note any sources that were unavailable>_
```

#### Formatting rules

- Use past tense, factual language — no editorializing
- Every ClickUp task must include a link: `[SW-XXXX](url)`
- Every Drive file must include a link: `[Filename](webViewLink)`
- Git highlights: briefly describe what the commits accomplished
  (e.g. "added gRPC reconnect logic, fixed backoff timer")
- Slack: summarize by channel and topic, not individual messages
  (unless there were very few)
- No blank lines before or after headings — keep compact
- For weekly reports, add a day-by-day breakdown under each member
- If a member had no activity from a source, write "No activity" in
  that section — do not omit the section

### Step 5 — Write the report

```bash
mkdir -p /workspaces/trl-work/reports
```

Write the markdown to `reports/team-report-<end_date>.md` using the
Write tool.

### Step 6 — Report to user

After writing, display:
- Output file path
- Date range covered
- Per-member summary (1 line each): top activity and counts
- Total metrics row
- Any sources that were unavailable

---

## Edge Cases

**No activity for a team member**: Keep their section but note
"No activity found in the reporting period" under each source.

**ClickUp member not found**: If a team member's name doesn't match
any workspace member, note it in the report footer and skip their
ClickUp data. Still gather git and other sources.

**No Slack token**: Skip Slack entirely. Note in the report footer:
"Slack data unavailable (no token)."

**Google API unavailable**: Skip Drive. Note in footer.

**Weekly reports**: For multi-day ranges, add a day-by-day commit
count table at the top of each member's Git Activity section:

```markdown
| Date | Commits |
|------|---------|
| Mon 3/31 | 5 |
| Tue 4/1  | 3 |
| ...      |   |
```

**Large date ranges (> 14 days)**: Warn the user that the report
may take a while and that Slack/Drive data may be incomplete due to
API pagination limits. Paginate ClickUp task searches fully.

**Existing report file**: Overwrite without asking — this is a
regenerated report.
