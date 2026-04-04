---
name: daily-journal
description: >
  Summarize everything Gabe did today and append it to today's journal entry
  in ClickUp (Gabe's Space > Journal). Use this skill whenever the user asks
  to summarize their day, log what they did today, update their journal with
  today's work, write an end-of-day summary, or says things like "wrap up my
  day", "add to my journal", "summarize today", "EOD summary", "what did I do
  today", or "log today's work". Always use this skill for any end-of-day or
  daily recap request that should be written to the ClickUp journal.
user-invokable: true
allowed-tools: Bash, Read, Agent
---

# Daily Journal Summary Skill

Gather signals from all connected sources, synthesize a concise end-of-day
summary, and append it to today's journal page in Gabe's ClickUp Journal doc.

All external service calls use CLI tools (`clickup`, `gws`) or `curl` for
Slack. Always use `--format json` with the ClickUp CLI for machine-readable
output. Parse JSON with `jq` or Python.

## Key Facts (hardcoded — do not ask)

| Field | Value |
|-------|-------|
| Journal doc ID | `kkbvf-4151` |
| Journal doc location | Gabe's Space in ClickUp |
| Page naming convention | `M/D` (e.g. `4/3` for April 3) |
| Page hierarchy | Journal -> YYYY -> MM - Mon -> M/D |
| Gabe's ClickUp user | resolve via `clickup workspace members` |
| Summary header | `# End of Day Summary` |

---

## CLI Reference

### ClickUp

```bash
# List workspace members (to get user ID)
clickup workspace members --format json

# Search tasks assigned to user, sorted by most recently updated
# NOTE: there is no --date-updated-gt flag — fetch recent tasks and
# filter client-side by comparing date_updated to start of day
clickup task search \
  --assignee <user_id> \
  --order-by updated \
  --reverse \
  --format json

# List time entries for today
clickup time list \
  --start "YYYY-MM-DD" \
  --end "YYYY-MM-DD" \
  --assignee <user_id> \
  --format json

# List document pages
clickup doc pages --doc-id <doc_id> --format json

# Get a document page
clickup doc page-get --doc-id <doc_id> --page-id <page_id> --format json

# Update a document page (replaces entire content)
clickup doc page-update \
  --doc-id <doc_id> \
  --page-id <page_id> \
  --content "$(cat /tmp/journal-page.md)"

# Create a document page
clickup doc page-create \
  --doc-id <doc_id> \
  --name "<M/D>" \
  --content "<markdown>" \
  --parent-page-id <parent_id>
```

### Google Workspace (gws)

**Important:** `gws` prints `Using keyring backend: keyring` to stderr.
Always append `2>/dev/null` when piping output to `jq` or Python, or the
extra line will break JSON parsing.

```bash
# Search Gmail messages sent today
gws gmail users messages list \
  --params '{"userId":"me","q":"after:YYYY/MM/DD in:sent"}' \
  --format json 2>/dev/null

# Read a specific email (metadata only)
gws gmail users messages get \
  --params '{"userId":"me","id":"<message_id>","format":"metadata","metadataHeaders":["Subject","To"]}' \
  --format json 2>/dev/null

# List today's calendar events
gws calendar events list \
  --params '{
    "calendarId":"primary",
    "timeMin":"YYYY-MM-DDT00:00:00Z",
    "timeMax":"YYYY-MM-DDT23:59:59Z",
    "singleEvents":true,
    "orderBy":"startTime"
  }' \
  --format json 2>/dev/null

# Search Drive for files modified today
gws drive files list \
  --params '{
    "q":"modifiedTime > '\''YYYY-MM-DDT00:00:00'\''",
    "orderBy":"modifiedTime desc",
    "fields":"files(id,name,webViewLink,modifiedTime,mimeType)",
    "pageSize":20
  }' \
  --format json 2>/dev/null
```

### Slack (via curl)

The `slack` CLI is for app development, not API access. Use `curl` with
the Slack user token from `~/.slack/credentials.json`.

**Scope limitation:** The Slack CLI token lacks `search:read` scope, so
`search.messages` will fail. Use `conversations.history` on specific
channels instead to read recent messages.

```bash
# Load token from Slack CLI credentials
SLACK_TOKEN="${SLACK_TOKEN:-$(python3 -c "
import json
with open('$HOME/.slack/credentials.json') as f:
    creds = json.load(f)
for ws in creds.values():
    print(ws.get('token', '')); break
" 2>/dev/null)}"

# List channels Gabe is a member of
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/users.conversations?types=public_channel,private_channel&limit=100" \
  | jq .

# Read recent messages from a specific channel
curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
  "https://slack.com/api/conversations.history?channel=<channel_id>&oldest=<unix_ts_start_of_day>&limit=50" \
  | jq .
```

To gather Slack activity: list channels, then read today's messages from
each channel. Filter for messages authored by `U038URT3K38` (Gabe's user
ID). Capture `text`, `channel`, and `permalink` for each message.

If the token is missing or API calls fail, skip Slack silently.

---

## Workflow

### Step 1 — Find today's journal page

List all pages in the Journal doc:

```bash
clickup doc pages --doc-id kkbvf-4151 --format json
```

Find the page whose `name` matches today's date in `M/D` format (e.g. `4/3`
for April 3). If no page exists yet for today, note that — you'll create one
later (see Edge Cases).

Read the current page content:

```bash
clickup doc page-get --doc-id kkbvf-4151 --page-id <page_id> --format json
```

Store the full existing content — you'll need it when writing back, because
`clickup doc page-update` **replaces** the entire page.

### Step 2 — Gather today's activity signals

Pull from all available sources in parallel where possible. For every item
collected, **always capture the direct URL or deep link** — this is required
for Step 3.

**ClickUp tasks** — tasks updated or closed today assigned to Gabe:

```bash
# Get user ID first
USER_ID=$(clickup workspace members --format json | jq -r '.[] | select(.user.username == "<username>") | .user.id')

# Search tasks updated today (use Unix ms for start of day)
START_MS=$(date -d "today 00:00:00" +%s)000
clickup task search \
  --assignee $USER_ID \
  --date-updated-gt $START_MS \
  --order-by updated \
  --reverse \
  --format json
```

For each task, capture: `custom_id` (e.g. `SW-4542`), `name`, `url`
(format: `https://app.clickup.com/t/<task_id>`), and `status`.

Also fetch time entries logged today:

```bash
clickup time list \
  --start "$(date +%Y-%m-%d)" \
  --end "$(date -d tomorrow +%Y-%m-%d)" \
  --assignee $USER_ID \
  --format json
```

**Slack** — read recent messages from channels Gabe is in.

The Slack CLI token lacks `search:read` scope, so use
`conversations.history` per channel instead of `search.messages`.

```bash
SLACK_TOKEN="${SLACK_TOKEN:-$(python3 -c "
import json
with open('$HOME/.slack/credentials.json') as f:
    creds = json.load(f)
for ws in creds.values():
    print(ws.get('token', '')); break
" 2>/dev/null)}"

if [ -n "$SLACK_TOKEN" ]; then
  # List channels Gabe is in
  curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
    "https://slack.com/api/users.conversations?types=public_channel,private_channel&limit=100" \
    2>/dev/null

  # For each channel, fetch today's messages
  START_TS=$(date -d "today 00:00:00" +%s)
  curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
    "https://slack.com/api/conversations.history?channel=<channel_id>&oldest=$START_TS&limit=50" \
    2>/dev/null
fi
```

Filter for messages where `user` is `U038URT3K38` (Gabe). Capture `text`,
channel name, and `permalink`. If token is missing or calls fail, skip
Slack silently.

**Gmail** — emails sent today:

```bash
gws gmail users messages list \
  --params '{"userId":"me","q":"after:'"$(date +%Y/%m/%d)"' in:sent"}' \
  --format json 2>/dev/null
```

For each message, read the full message to get subject and recipients:

```bash
gws gmail users messages get \
  --params '{"userId":"me","id":"<message_id>","format":"metadata","metadataHeaders":["Subject","To"]}' \
  --format json 2>/dev/null
```

Summarize by subject only (Gmail messages don't have sharable deep links).

**Google Calendar** — events today:

```bash
gws calendar events list \
  --params '{
    "calendarId":"primary",
    "timeMin":"'"$(date +%Y-%m-%d)"'T00:00:00Z",
    "timeMax":"'"$(date +%Y-%m-%d)"'T23:59:59Z",
    "singleEvents":true,
    "orderBy":"startTime"
  }' \
  --format json 2>/dev/null
```

Capture event `summary`, `attendees`, and `htmlLink` URL. Events are in
the `items` array of the response.

**Google Drive** — documents created or modified today:

```bash
gws drive files list \
  --params '{
    "q":"modifiedTime > '\'''"$(date +%Y-%m-%d)"'T00:00:00'\''",
    "orderBy":"modifiedTime desc",
    "fields":"files(id,name,webViewLink,modifiedTime,mimeType)",
    "pageSize":20
  }' \
  --format json 2>/dev/null
```

Capture file `name` and `webViewLink`. Files are in the `files` array.

**Git commits** — commits authored by Gabe today across all workspace repos.
First, use `gh` to check which repos have new commits on GitHub and only
fetch those (avoids slow fetch-all across every repo):

```bash
for repo in /workspaces/trl-work/*/; do
  [ -d "$repo/.git" ] || continue
  remote=$(git -C "$repo" remote get-url origin 2>/dev/null)
  gh_repo=$(echo "$remote" | sed 's|.*github.com[:/]||;s|\.git$||')
  branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null)
  remote_sha=$(gh api "repos/$gh_repo/branches/$branch" --jq '.commit.sha' 2>/dev/null)
  local_sha=$(git -C "$repo" rev-parse HEAD 2>/dev/null)
  if [ -n "$remote_sha" ] && [ "$remote_sha" != "$local_sha" ]; then
    echo "Syncing $(basename "$repo") ($branch)..."
    git -C "$repo" fetch origin "$branch" 2>&1
    git -C "$repo" merge-base --is-ancestor HEAD "origin/$branch" 2>/dev/null && \
      git -C "$repo" pull --ff-only 2>&1
  fi
done
```

Then scan for today's commits:

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

For each commit, capture the repo name, short hash, and subject line. Group
by repo in the summary and briefly describe what the commits accomplished
(e.g. "merged VimbaX upgrade into dev, installed tudat resources into BSP").

Do not ask Gabe to provide any of this — gather it automatically.

### Step 3 — Synthesize the summary

Write a concise, narrative end-of-day summary that:

- Opens with a 1-3 sentence "headline" capturing the day's main theme
- Groups work into logical sections (e.g. by project: SAVER, Xclops NG,
  IQT, infrastructure, meetings, etc.)
- Within each section, uses short bullet points — what was done, any
  blockers, outcomes, or next steps if obvious
- Mentions key people interacted with (meetings, Slack threads, reviews)
- Notes any deliverables produced, PRs opened/merged, tickets closed
- Keeps total length to roughly 150-400 words — enough to be useful
  when read months later, short enough to write every day
- Uses past tense, first person implied ("Worked on...", "Reviewed...")

**Every substantive item must include a link.** Use markdown inline links
so the journal is navigable. Follow these conventions per source:

| Source | Link format |
|--------|-------------|
| ClickUp task | `[SW-4542 Task Name](https://app.clickup.com/t/<id>)` — use custom ID as the label prefix |
| Slack thread | `[#channel-name thread](permalink_url)` |
| Google Calendar event | `[Meeting Title](htmlLink)` |
| Google Drive file | `[Filename](webViewLink)` |
| ClickUp doc/page | `[Doc Name](https://app.clickup.com/<workspace>/docs/<doc_id>/<page_id>)` |

Example bullet with links:
```
- Continued work on [SW-4821 Xclops NG gRPC reconnect logic](https://app.clickup.com/t/868abc123) — fixed the
  backoff timer, left a note in the [#sw-xclops thread](https://slack.com/...)
```

**Section order preference** (skip if no activity):
1. Main engineering work (most time)
2. Meetings & syncs
3. Reviews / documentation
4. Misc / admin

### Step 4 — Preview or write

Check the user's invocation for the word "preview". If the user said
"preview", "show me a preview", or `/daily-journal preview`:

- **Preview mode**: Write the synthesized summary to
  `reports/daily-journal-preview.md` and display the full text in the
  conversation. Do NOT write to ClickUp. Ask the user if it looks good.
  If they approve, proceed to write it to ClickUp. If they request
  changes, revise, update the preview file, and show again.

- **Default mode** (no "preview" keyword): Write directly to ClickUp
  without asking. This is the normal flow. Also write a copy to
  `reports/daily-journal-preview.md` so the last entry is always
  available locally.

#### Writing to ClickUp

Construct the updated page content by writing it to a temp file:

```bash
cat > /tmp/journal-page.md << 'PAGEEOF'
<existing page content>
# End of Day Summary
*<Today's date, written out, e.g. "Friday, April 3, 2026">*
<synthesized summary — no blank lines before or after headings>
PAGEEOF

clickup doc page-update \
  --doc-id kkbvf-4151 \
  --page-id <today_page_id> \
  --content "$(cat /tmp/journal-page.md)"
```

**Important**: Preserve all existing content verbatim. Only append — never
modify or reformat what's already there.

### Step 5 — Confirm

Tell Gabe:
- That the summary was appended to today's journal entry
- Provide a brief 2-3 line preview of what was written
- Offer to adjust tone, length, or add/remove anything

---

## Edge Cases

**No journal page exists for today**: Create one first:

```bash
# Find the current month page (e.g. "04 - Apr") in the page list
clickup doc page-create \
  --doc-id kkbvf-4151 \
  --name "<M/D>" \
  --content "" \
  --parent-page-id <current_month_page_id>
```

To find the correct parent (the current month page), look at the page list
for a page matching the current month (e.g. `04 - Apr`). If that month page
doesn't exist either, create it under the current year page first.

**Summary section already exists**: If `# End of Day Summary` is already
in the page content, append a new one with a timestamp suffix in the header
(e.g. `# End of Day Summary (updated 5:30 PM)`) rather than overwriting.

**No activity signals found**: If a source returns nothing (quiet Slack day,
no calendar events, etc.), simply omit that section. Don't mention the absence
unless it's notable (e.g. "No meetings today").

**User provides additional context**: If Gabe adds context in the trigger
message (e.g. "summarize my day, I also worked on the SAVER FPC issue"),
incorporate it prominently into the summary.

**No Slack token available**: Skip Slack data gathering entirely. Do not
error — just proceed with the other sources.

---

## Tone & Style Notes

- Match the informal, technical shorthand already present in Gabe's journal
  (e.g. "SAVER", "Xclops NG", "Jetson", colleague first names)
- Don't editorialize or add opinions — factual and concise
- Bullet points > paragraphs for the body; prose only for the opening headline
- No blank lines before or after headings in the journal output — keep the summary compact. For example:
  ```
  ### Xclops NG / SAVER
  - Merged the VimbaX upgrade...
  ### Meetings & Syncs
  - TRL11 <> Unaware Sensing...
  ```
  NOT:
  ```
  ### Xclops NG / SAVER

  - Merged the VimbaX upgrade...

  ### Meetings & Syncs

  - TRL11 <> Unaware Sensing...
  ```
- Colleague names: use first names only (Nate, Jackson, Connor, Said, Aneesh,
  John, Trevin, Graham, Ryan, Dennis, Pearl)
