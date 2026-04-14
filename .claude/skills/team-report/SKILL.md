---
name: team-report
description: >
  Generate an SW team activity report covering git commits, ClickUp tasks,
  Google Drive edits, and Slack messages for Gabe, Said, and Jackson.
  Groups work by product/mission with narrative summaries showing who did
  what. Writes to ClickUp journal and reports/. Use this skill when the
  user asks for a team report, team summary, team activity, SW team status,
  or says things like "what did the team do", "team report for last week",
  "SW activity summary", or "generate team report".
user-invokable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# SW Team Activity Report

Gather activity signals from git, ClickUp, Google Drive, and Slack for
the SW team, then synthesize a narrative report grouped by product/mission.

## Team Members

| Name | Role | ClickUp ID |
|------|------|------------|
| Gabe | SW Lead | 38406330 |
| Said | SW Engineer | 75314186 |
| Jackson | SW Engineer | 87301942 |

## Subcommands

| Invocation | Action |
|------------|--------|
| `/team-report` | Report for the most recently ended Mon–Sun week |
| `/team-report preview` | Same, but write locally only — ask before pushing to ClickUp |
| `/team-report last week` | Last Mon–Sun week |
| `/team-report 3/30-4/5` | Specific date range (M/D-M/D) |
| `/team-report today` / `yesterday` | Single-day report |
| `/team-report March` / `last month` | Full calendar month |

**Default behavior** (no arguments): report for the most recently
completed Mon–Sun week. If today is Sunday, use the week ending today.

Preview is the default unless the user explicitly says "publish",
"push", or "write to ClickUp".

## Date Range Parsing

| Input | Range |
|-------|-------|
| _(none / "last week")_ | Most recently ended Mon–Sun week |
| `this week` | Current week Mon through today |
| `today` | Start of today through now |
| `yesterday` | Yesterday 00:00 – 23:59 |
| `M/D-M/D` | Exact range (current year assumed) |
| `YYYY-MM-DD` to `YYYY-MM-DD` | Exact range |
| `March`, `last month` | Full calendar month |

Multi-day = **Weekly Team Report**. Single-day = **Daily Team Report**.

## Output

| Destination | Path |
|-------------|------|
| Preview file | `reports/team-report-preview.md` |
| Local archive | `reports/team-report-YYYY-MM-DD.md` (end date) |
| ClickUp journal | Journal → YYYY → MM - Mon → `Team Report (M/D-M/D)` |

## Key Facts (hardcoded — do not ask)

| Field | Value |
|-------|-------|
| Journal doc ID | `kkbvf-4151` |
| Workspace ID | `20557679` |
| ClickUp API token | Read from `~/.config/clickup-cli-nodejs/config.json` → `profiles.default.token` |
| Page naming | `Team Report (M/D-M/D)` or `Team Report (M/D)` for single-day |
| Local backup dir | `reports/journal/` |
| Index file | `reports/journal/_index.json` |

---

## Workflow

### Step 1 — Determine date range

Parse the user's input. Store `START_DATE`, `END_DATE`, and
`END_DATE_PLUS_ONE`.

For default/week mode:
```python
from datetime import date, timedelta

today = date.today()
if today.weekday() == 6:
    sunday = today
else:
    sunday = today - timedelta(days=(today.weekday() + 1))
monday = sunday - timedelta(days=6)
```

### Step 2 — Gather data

Pull all four sources in parallel using separate Bash calls.

#### Git

```bash
for repo in /workspaces/trl-work/*/; do
  [ -d "$repo/.git" ] || continue
  commits=$(git -C "$repo" log \
    --after="<START_DATE>T00:00:00" \
    --before="<END_DATE_PLUS_ONE>T00:00:00" \
    --author="gabe\|Gabe\|said\|Said\|jackson\|Jackson" \
    --format="%h|%an|%ad|%s" --date=short 2>/dev/null)
  [ -n "$commits" ] && echo "=== $(basename "$repo") ===" && echo "$commits"
done
```

#### ClickUp Tasks

```bash
START_MS=$(date -d "<START_DATE> 00:00:00" +%s)000

for uid in 38406330 75314186 87301942; do
  clickup task search --assignee $uid --order-by updated --reverse --format json 2>/dev/null
done
```

Filter client-side: keep tasks where `int(date_updated) >= START_MS`.
For closed tasks, add `--include-closed` and filter by `date_done`.

For each task capture: `custom_id`, `name`, `status`, `url`.

#### ClickUp Time Entries

```bash
for uid in 38406330 75314186 87301942; do
  clickup time list --start "<START_DATE>" --end "<END_DATE>" --assignee $uid --format json 2>/dev/null
done
```

#### Google Drive

```bash
gws drive files list \
  --params '{
    "q":"modifiedTime > '\''"<START_DATE>T00:00:00"'\'' and modifiedTime < '\''"<END_DATE>T23:59:59"'\''",
    "orderBy":"modifiedTime desc",
    "fields":"files(id,name,webViewLink,modifiedTime,mimeType,lastModifyingUser)",
    "pageSize":50
  }' \
  --format json 2>/dev/null
```

Always append `2>/dev/null` when piping `gws` output. Filter by
`lastModifyingUser.displayName` matching team member names. If
unavailable, skip silently.

#### Slack

```bash
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

for user in gabe said jackson; do
  curl -s -H "Authorization: Bearer $SLACK_TOKEN" \
    --data-urlencode "query=from:$user after:<START_DATE> before:<END_DATE_PLUS_ONE>" \
    "https://slack.com/api/search.messages?count=100"
done
```

Results in `.messages.matches[]` — capture `text`, `channel.name`,
`permalink`. Paginate if `paging.pages > 1`. If token missing/expired,
skip silently and note in report footer.

### Step 3 — Group by product/mission

Scan all gathered data and dynamically identify product/mission
groupings. Attribute each item to a team member.

**How to detect groupings:**
1. Map repos to products: `trl-xclops-ng` → Xclops NG,
   `trl-commander` → Commander, `trl-saver` → SAVER,
   `trl-viplink` → VIPLink, `trl-jetson-bsp` → BSP/Infrastructure,
   `trl-forge` → Forge, etc.
2. Map ClickUp tickets by prefix and name to products
3. Look for recurring themes across git, tasks, and Slack
4. Cluster related items under the most descriptive label
5. Merge small groups (1-2 items) into a broader category or "Other"
6. Order groups by volume of activity (most active first)

Common groupings (detect dynamically, don't hardcode):
- Product names: SAVER, Xclops NG, VIPLink, VIPOnly/LUMI, Forge,
  OrbitVision, FoveaCTL, Commander, etc.
- Mission names: Haven-1, QC Pro, IQT, Shield Space, Starfish, etc.
- Infrastructure: Jenkins, Gitea, BSP, devcontainer, build system
- Meetings & coordination
- Hardware / integration

### Step 4 — Synthesize the report

Write a narrative report that:

- Opens with a 2-4 sentence overview of the team's week
- Groups work into sections by product/mission (detected in Step 3)
- Within each section, uses bullet points describing what was
  accomplished and **who did it** (first name)
- Mentions collaboration between team members where visible
- Notes significant deliverables, PRs merged, milestones hit
- Includes minor items in appropriate sections or a Misc section
- Keeps total length to 400-1000 words (scales with activity)
- Uses past tense, third person ("Gabe built...", "Jackson fixed...")

**Summarize, don't enumerate commits.** For example:
- BAD: "Jackson committed `abc123`, `def456`, `ghi789` to fix files"
- GOOD: "Jackson fixed VIP1st file cascading and added thumbnail
  cleanup on deletion"

**But include all notable work items.** Don't drop minor fixes or
admin items. Group them logically.

**Preserve key references:**
- ClickUp ticket links for significant items: `[SW-XXXX](url)`
- Merge commit hashes for notable merges: `` `e56787d7` ``
- Don't include every individual commit hash — only merges and
  significant standalone commits

**Section format:**

```markdown
## Product/Mission Name
- What Gabe accomplished on this product
- What Jackson worked on
- Notable: [SW-XXXX](url), merged `hash`
```

**Section order:**
1. Main engineering sections (largest first)
2. Infrastructure / tooling
3. Meetings & collaboration (if notable)
4. Hardware / integration (if applicable)
5. Misc / admin (only if notable)

Skip sections with no activity — don't mention their absence.

**End with a compact metrics table:**

```markdown
---
| Member | Commits | Tasks | Hours | Slack |
|--------|---------|-------|-------|-------|
```

### Step 5 — Output

#### Preview mode (default)

Write the report to `reports/team-report-preview.md` using the Write
tool. Display it in the conversation. Ask the user:

> Ready to publish to ClickUp as "Team Report (M/D-M/D)"? (yes/no)

If yes, proceed to publish. If no, ask what to change.

#### Publish mode

1. Find the parent month page in ClickUp for the end date.
   Look up `_index.json` for month pages, or list pages to find the
   correct `MM - Mon` page under the year.

2. Check if a "Team Report (M/D-M/D)" page already exists:
   - If yes, read existing content and replace it
   - If no, create a new page

3. Create or update the page:

   ```bash
   CLICKUP_TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.config/clickup-cli-nodejs/config.json'))['profiles']['default']['token'])")

   curl -s -X POST \
     "https://api.clickup.com/api/v3/workspaces/20557679/docs/kkbvf-4151/pages" \
     -H "Authorization: $CLICKUP_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$(python3 -c "
   import json
   with open('/tmp/team-report.md') as f:
       content = f.read()
   print(json.dumps({
       'name': 'Team Report (<M/D-M/D>)',
       'parent_page_id': '<month_page_id>',
       'content': content
   }))
   ")"

   # Or update existing page
   clickup doc page-update \
     --doc-id kkbvf-4151 \
     --page-id <page_id> \
     --content "$(cat /tmp/team-report.md)"
   ```

4. Also save a local copy to `reports/team-report-YYYY-MM-DD.md`.

### Step 6 — Report to user

After publishing, display:
- Date range covered
- Product/mission groupings found
- Team member activity summary (commits, hours)
- ClickUp page link (if published)

---

## Report Template

```markdown
# SW Team Report
_<date range> | Generated: <today>_

<2-4 sentence narrative overview of the team's main accomplishments.>

## Xclops NG
- Gabe built Ximea camera plugin with xiAPI SDK integration, including
  GStreamer source element, unit tests, and thread safety fixes
- Gabe added Haivision Makito decoder UI and controller service
  ([SW-4723](url)), merged `e56787d7`
- Jackson fixed fovea remote control page ([SW-4717](url))

## Commander
- Jackson implemented VIP1st file integration and display, with
  thumbnail cleanup and file transfer pagination fixes
- Jackson worked on dashboard improvements ([SW-4693](url)) and
  snapshot retry logic

## SAVER
- Gabe streamlined SDK release package and updated PR template
  to use `make verify` ([SW-4722](url))

## BSP / Infrastructure
- Gabe upgraded VimbaX SDK to 2026-1 across Jetson BSP and Xclops
- Gabe added Software Activation (SWA) package and zstd mass flash

## Hardware / Integration
- Said completed Naden Class 2 unit build support ([MIS-2311](url))
  and GSE flashing setup ([EE-647](url))

---
| Member | Commits | Tasks Updated | Hours Logged |
|--------|---------|---------------|--------------|
| Gabe | 104 | 12 | 20.0 |
| Said | 0 | 12 | 0.0 |
| Jackson | 28 | 11 | 34.5 |

_Sources: Git, ClickUp, Google Drive, Slack_
```

---

## Edge Cases

- **No activity for a member**: Don't create a section for them —
  mention in overview if notable
- **No Slack token / expired**: Skip Slack, note in footer
- **Drive unavailable**: Skip Drive, note in footer
- **> 14 days**: Warn about Slack/Drive pagination limits
- **Existing file/page**: Overwrite without asking
- **Single-day report**: Use `Team Report (M/D)` page name

---

## Tone & Style

- Match the journal's informal, technical shorthand
- Factual and concise — no editorializing
- Bullet points > paragraphs; prose only for the opening overview
- No blank lines before or after headings (compact formatting)
- First names only for colleagues
- Higher-level than raw data — focus on outcomes and narrative,
  not commit-by-commit enumeration
- Attribute work to team members within product sections
  ("Gabe built...", "Jackson fixed...")
