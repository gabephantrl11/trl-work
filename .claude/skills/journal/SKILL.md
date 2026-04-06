---
name: journal
description: >
  Manage Gabe's ClickUp Journal — sync/backup to local disk, search entries,
  read specific days, or write end-of-day summaries. Use this skill when the
  user asks to search their journal, sync/backup journal pages, read a journal
  entry, summarize their day, or says things like "search my journal for X",
  "sync journal", "backup journal", "journal search", "wrap up my day",
  "EOD summary", "summarize today", "what did I write about X", "read my
  journal for M/D", or "journal read 3/15".
user-invokable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# Journal Skill

Unified skill for Gabe's ClickUp Journal (doc `kkbvf-4151`). Supports four
subcommands: `sync`, `search`, `read`, and `summary`.

## Subcommands

| Invocation | Action |
|------------|--------|
| `/journal sync` | Backup all journal pages to local disk. Incremental by default. |
| `/journal sync --full` | Force re-fetch of all pages. |
| `/journal search <query>` | Grep local backup for a keyword/pattern. Auto-syncs if no backup. |
| `/journal read [M/D]` | Read a specific day's entry. Defaults to today. |
| `/journal summary` | Gather today's activity signals and write an end-of-day summary. |

**Default behavior** (no explicit subcommand): if the user provides a search
term, treat it as `search`. If no arguments, show help.

---

## Key Facts (hardcoded — do not ask)

| Field | Value |
|-------|-------|
| Journal doc ID | `kkbvf-4151` |
| Workspace ID | `20557679` |
| ClickUp API token | Read from `~/.config/clickup-cli-nodejs/config.json` → `profiles.default.token` |
| Page hierarchy | Journal → YYYY → MM - Mon → M/D |
| Page naming | `M/D` (e.g. `4/3` for April 3) |
| Local backup dir | `reports/journal/` |
| Index file | `reports/journal/_index.json` |
| Gabe's ClickUp user ID | `38406330` |
| Gabe's Slack user ID | `U038URT3K38` |
| Summary header | `# End of Day Summary` |

---

## Sync Subcommand

Backs up journal pages from ClickUp to `reports/journal/` as plain markdown
files, making them searchable with grep.

### Local backup structure

```
reports/journal/
  _index.json
  2024/
    01/
      1-5.md
      1-6.md
    04/
      4-3.md
  2025/
    ...
  2026/
    04/
      4-3.md
      4-4.md
```

Day pages use `M-D.md` filenames (dash instead of slash). Month directories
use zero-padded numbers (`01`, `02`, ..., `12`).

### `_index.json` format

```json
{
  "doc_id": "kkbvf-4151",
  "last_sync": "2026-04-04T15:30:00Z",
  "total_pages": 443,
  "pages": {
    "kkbvf-48571": {
      "name": "4/4",
      "year": "2026",
      "month": "04",
      "local_path": "2026/04/4-4.md"
    }
  }
}
```

### Sync workflow

Run a Python script via Bash that does the full sync in one execution:

1. Read the ClickUp API token from `~/.config/clickup-cli-nodejs/config.json`
2. Call the ClickUp v3 API to list all pages:
   ```
   GET https://api.clickup.com/api/v3/workspaces/20557679/docs/kkbvf-4151/pages
   Authorization: <token>
   ```
3. Parse the nested page tree to find the "Journal" top-level page
4. Walk the Journal subtree to identify all day pages (leaf nodes with `M/D`
   name format), tracking the current year and month from parent pages
5. Load `_index.json` if it exists to determine which pages are already synced
6. For each **new** page (not in index), fetch content:
   ```bash
   clickup doc page-get --doc-id kkbvf-4151 --page-id <page_id> --format json
   ```
7. Write the page content to `reports/journal/{year}/{month}/{M-D}.md`
8. Update `_index.json` with the new pages and timestamp

For `--full` mode: skip step 5 comparison and re-fetch all pages.

**Important**: The page tree is nested. Year pages contain month pages,
month pages contain day pages. Track the hierarchy as you recurse:

```python
def walk_pages(pages, year=None, month=None):
    day_pages = []
    for page in pages:
        name = page["name"]
        pid = page["id"]
        children = page.get("pages", [])

        # Year page: 4-digit number
        if name.isdigit() and len(name) == 4:
            day_pages.extend(walk_pages(children, year=name, month=None))
        # Month page: "04 - Apr" format
        elif " - " in name and year:
            m = name.split(" - ")[0]
            day_pages.extend(walk_pages(children, year=year, month=m))
        # Day page: "M/D" format (leaf node with content)
        elif "/" in name and year and month:
            day_pages.append({
                "id": pid,
                "name": name,
                "year": year,
                "month": month,
            })
            # Day pages can also have children (sub-notes) — skip those
        else:
            # Unknown page type — recurse anyway
            day_pages.extend(walk_pages(children, year=year, month=month))

    return day_pages
```

**Rate limiting**: Add a small delay (0.1s) between page-get calls to
avoid hitting the ClickUp API rate limit. For a full sync of ~443 pages,
this takes about 45 seconds.

### Progress reporting

Print progress every 25 pages:
```
Syncing journal... 25/443 pages fetched
Syncing journal... 50/443 pages fetched
...
Sync complete: 443 pages (12 new, 431 cached)
```

---

## Search Subcommand

Searches the local journal backup using grep.

### Workflow

1. Check if `reports/journal/_index.json` exists
   - If not: run sync first, then search
   - If yes: proceed to search (optionally run a quick incremental sync
     for the current month to catch today's entries)
2. Use the Grep tool on `reports/journal/` with the user's query:
   - Use `-C 3` for context lines
   - Use `-i` for case-insensitive by default
   - Exclude `_index.json` from results
3. Present results grouped by date:
   - Derive the date from the file path (e.g. `2026/04/4-3.md` → April 3, 2026)
   - Show the matching lines with surrounding context
   - For each match, mention the date prominently

### Example output

```
### April 3, 2026 (2026/04/4-3.md)
> Added nasm to dependencies for FFmpeg x86 assembly support (`489c34a0`)

### March 15, 2026 (2026/03/3-15.md)
> ...discussed nasm build requirements with Said...
```

---

## Read Subcommand

Reads a specific journal day entry.

### Workflow

1. Parse the date argument:
   - `M/D` format (e.g. `4/3`) — use current year
   - `M/D/YYYY` format — use specified year
   - No argument — use today's date
2. Check local backup first: `reports/journal/{year}/{month}/{M-D}.md`
3. If not found locally, fetch from ClickUp:
   ```bash
   clickup doc page-get --doc-id kkbvf-4151 --page-id <page_id> --format json
   ```
   Look up the page ID from `_index.json`, or list pages to find it.
4. Display the content

---

## Summary Subcommand

Gathers today's activity signals from all connected sources, synthesizes a
concise end-of-day summary, and appends it to today's journal page in ClickUp.

### CLI Reference

#### ClickUp

```bash
# Search tasks assigned to Gabe, sorted by most recently updated
clickup task search \
  --assignee 38406330 \
  --order-by updated \
  --reverse \
  --format json

# List time entries for today
clickup time list \
  --start "YYYY-MM-DD" \
  --end "YYYY-MM-DD" \
  --assignee 38406330 \
  --format json

# Get a document page
clickup doc page-get --doc-id kkbvf-4151 --page-id <page_id> --format json

# Update a document page (replaces entire content)
clickup doc page-update \
  --doc-id kkbvf-4151 \
  --page-id <page_id> \
  --content "$(cat /tmp/journal-page.md)"

# Create a document page
clickup doc page-create \
  --doc-id kkbvf-4151 \
  --name "<M/D>" \
  --content "<markdown>" \
  --parent-page-id <parent_id>
```

#### Google Workspace (gws)

**Important:** `gws` prints `Using keyring backend: keyring` to stderr.
Always append `2>/dev/null` when piping output to `jq` or Python.

```bash
# Gmail — emails sent today
gws gmail users messages list \
  --params '{"userId":"me","q":"after:YYYY/MM/DD in:sent"}' \
  --format json 2>/dev/null

# Gmail — read specific email metadata
gws gmail users messages get \
  --params '{"userId":"me","id":"<message_id>","format":"metadata","metadataHeaders":["Subject","To"]}' \
  --format json 2>/dev/null

# Calendar — today's events
gws calendar events list \
  --params '{
    "calendarId":"primary",
    "timeMin":"YYYY-MM-DDT00:00:00Z",
    "timeMax":"YYYY-MM-DDT23:59:59Z",
    "singleEvents":true,
    "orderBy":"startTime"
  }' \
  --format json 2>/dev/null

# Drive — files modified today
gws drive files list \
  --params '{
    "q":"modifiedTime > '\''YYYY-MM-DDT00:00:00'\''",
    "orderBy":"modifiedTime desc",
    "fields":"files(id,name,webViewLink,modifiedTime,mimeType)",
    "pageSize":20
  }' \
  --format json 2>/dev/null
```

#### Slack (via curl)

Use the Slack token from `~/.slack/credentials.json` (the CLI token has
`channels:history` and `groups:history` scopes).

```bash
SLACK_TOKEN=$(python3 -c "
import json
with open('$HOME/.slack/credentials.json') as f:
    creds = json.load(f)
for ws in creds.values():
    print(ws.get('token', '')); break
" 2>/dev/null)

# Per-channel history scanning (search:read scope is missing)
# Get channel list, then scan each for messages from U038URT3K38
```

If the token is missing or API calls fail, skip Slack silently.

### Signal gathering workflow

Pull from all available sources in parallel where possible. For every item
collected, **always capture the direct URL or deep link**.

**ClickUp tasks** — tasks updated or closed today assigned to Gabe:

```bash
clickup task search \
  --assignee 38406330 \
  --order-by updated \
  --reverse \
  --format json
```

Filter client-side by comparing `date_updated` to start of today (Unix ms).
For each task, capture: `custom_id`, `name`, `url`, and `status`.

Also fetch time entries logged today.

**Slack** — scan channels for Gabe's messages today. Use `conversations.list`
then `conversations.history` per channel, filtering for `user == U038URT3K38`
and `ts >= start_of_today`. If token missing or calls fail, skip silently.

**Gmail** — emails sent today. For each, read metadata for subject and
recipients. Summarize by subject only.

**Google Calendar** — events today with attendees and `htmlLink`.

**Google Drive** — files modified today with `webViewLink`.

**Git commits** — commits authored by Gabe today across workspace repos:

```bash
for repo in /workspaces/trl-work/*/; do
  if [ -d "$repo/.git" ]; then
    commits=$(git -C "$repo" log --oneline \
      --after="$(date +%Y-%m-%d)T00:00:00" \
      --before="$(date -d tomorrow +%Y-%m-%d)T00:00:00" \
      --author="gabe\|Gabe" 2>/dev/null)
    if [ -n "$commits" ]; then
      echo "=== $(basename "$repo") ==="
      echo "$commits"
    fi
  fi
done
```

**Important**: The `--oneline` output includes the short hash and subject
(e.g. `489c34a0 Add nasm to dependencies`). Preserve these hashes — they
MUST appear in the final summary in backticks (e.g. `` `489c34a0` ``).
Group related commits into narrative bullets but always include the hashes.

### Synthesize the summary

Write a concise, narrative end-of-day summary that:

- Opens with a 1-3 sentence "headline" capturing the day's main theme
- Groups work into logical sections (by project: SAVER, Xclops NG, IQT,
  infrastructure, meetings, etc.)
- Within each section, uses short bullet points
- Mentions key people interacted with
- Notes deliverables, PRs opened/merged, tickets closed
- Keeps total length to roughly 150-400 words
- Uses past tense, first person implied ("Worked on...", "Reviewed...")

**Every substantive item must include a link and/or reference hash.**
This is critical — the journal must be navigable months later.

| Source | Link format | Example |
|--------|-------------|---------|
| ClickUp task | `[SW-4542 Task Name](https://app.clickup.com/t/<task_id>)` | `[SW-4730 Ximea camera integration](https://app.clickup.com/t/868j4hddd)` |
| Git commit | Include short hash in backticks after the description | `Added nasm for FFmpeg x86 assembly (\`489c34a0\`)` |
| Git merge/PR | Include hash + branch name | `Merged feature/SW-4723-Haivision-Makito-ctl into dev (\`e56787d7\`)` |
| Git (multiple related commits) | Summarize the work, list key hashes | `Built Ximea plugin from scratch (\`f808f771\`), added tests (\`402d28f6\`), fixed thread safety (\`55d6909e\`)` |
| Slack thread | `[#channel-name thread](permalink_url)` | `[#sw-xclops thread](https://trl11.slack.com/archives/...)` |
| Slack DM | `[Name via DM](permalink_url)` | `[Nate via DM](https://trl11.slack.com/archives/D06173H61S8/p...)` |
| Google Calendar | `[Meeting Title](htmlLink)` | `[IQT Deliverables Discussion](https://www.google.com/calendar/event?eid=...)` |
| Google Drive | `[Filename](webViewLink)` | `[SDK v3.2.0](https://drive.google.com/drive/folders/...)` |
| ClickUp doc/page | `[Doc Name](https://app.clickup.com/20557679/v/dc/<doc_id>/<page_id>)` | |

**Git commit hashes are mandatory.** Every bullet that references git work
must include at least one short hash (7-8 chars) in backticks. When
summarizing multiple commits into one bullet, include the most significant
hashes (merges, key features). This makes the journal traceable back to
exact code changes.

**Section order** (skip if no activity):
1. Main engineering work
2. Meetings & syncs
3. Reviews / documentation
4. Misc / admin

### Writing to ClickUp

1. Find today's page: look up `M/D` in `_index.json`, or list pages to find it
2. If no page exists for today, create one under the current month page:
   ```bash
   clickup doc page-create \
     --doc-id kkbvf-4151 \
     --name "<M/D>" \
     --content "" \
     --parent-page-id <current_month_page_id>
   ```
3. Read the current page content (preserve it verbatim)
4. Append the summary after existing content
5. Write back via `page-update` (replaces entire content, so include everything)

Check the user's invocation for "preview":
- **Preview mode**: Write to `reports/daily-journal-preview.md`, display in
  conversation, ask for approval before writing to ClickUp
- **Default mode**: Write directly to ClickUp, also save a local copy

**If `# End of Day Summary` already exists** in the page, append a new one
with a timestamp suffix (e.g. `# End of Day Summary (updated 5:30 PM)`).

### Updating local backup after summary

After writing to ClickUp, also update the local backup file at
`reports/journal/{year}/{month}/{M-D}.md` with the new content.

---

## Edge Cases

**No local backup exists (for search/read)**: Run sync automatically first.

**No journal page for today (for summary)**: Create the page. If the current
month page doesn't exist, create it under the year page first.

**User provides additional context for summary**: Incorporate it prominently.

**No activity signals found**: Omit empty sections. Don't mention the absence
unless notable.

**No Slack token**: Skip Slack silently.

---

## Tone & Style Notes (for summary)

- Match informal, technical shorthand (SAVER, Xclops NG, Jetson)
- Factual and concise — no editorializing
- Bullet points > paragraphs; prose only for the headline
- No blank lines before or after headings (compact formatting)
- Colleague names: first names only (Nate, Jackson, Connor, Said, Aneesh,
  John, Trevin, Graham, Ryan, Dennis, Pearl)
