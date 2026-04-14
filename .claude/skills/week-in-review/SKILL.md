---
name: week-in-review
description: >
  Generate a weekly summary journal entry from daily journal pages,
  grouped by product/mission. Reads Mon–Sun daily entries from the
  local journal backup, synthesizes them into a concise week-in-review,
  and writes it to ClickUp as a journal page. Use this skill when the
  user asks for a weekly summary, week in review, weekly journal, or
  says things like "summarize the week", "week in review", "weekly
  wrap-up", "what happened this week".
user-invokable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# Week-in-Review Skill

Reads daily journal entries for a Mon–Sun week, groups work by
product/mission, and creates a summary journal page in ClickUp.

## Subcommands

| Invocation | Action |
|------------|--------|
| `/week-in-review` | Summarize the most recently ended Mon–Sun week |
| `/week-in-review preview` | Same, but write locally only — ask before pushing to ClickUp |
| `/week-in-review 3/30-4/5` | Summarize a specific week (M/D-M/D) |
| `/week-in-review 3/30-4/5 preview` | Specific week, preview mode |

**Default behavior** (no arguments): summarize the most recently
completed Mon–Sun week. If today is Sunday, summarize the week that
ends today. Otherwise, summarize the week that ended last Sunday.

Preview is the default unless the user explicitly says "publish",
"push", or "write to ClickUp".

---

## Key Facts (hardcoded — do not ask)

| Field | Value |
|-------|-------|
| Journal doc ID | `kkbvf-4151` |
| Workspace ID | `20557679` |
| ClickUp API token | Read from `~/.config/clickup-cli-nodejs/config.json` → `profiles.default.token` |
| Page hierarchy | Journal → YYYY → MM - Mon → Week of M/D-M/D |
| Page naming | `Week of M/D-M/D` (e.g. `Week of 3/30-4/5`) |
| Local backup dir | `reports/journal/` |
| Index file | `reports/journal/_index.json` |
| Preview file | `reports/weekly-review-preview.md` |
| Summary header | `# Week in Review` |

---

## Workflow

### Step 1 — Determine date range

Parse the user's input to find the Mon–Sun range. If no dates given,
compute the most recently ended week:

```python
from datetime import date, timedelta

today = date.today()
# If today is Sunday, use this week (Mon = today - 6)
if today.weekday() == 6:
    sunday = today
else:
    # Last Sunday
    sunday = today - timedelta(days=(today.weekday() + 1))
monday = sunday - timedelta(days=6)
```

Store `monday` and `sunday` as the range endpoints.

The page name uses `M/D-M/D` format with no leading zeros:
`Week of {mon.month}/{mon.day}-{sun.month}/{sun.day}`

### Step 2 — Read daily journal entries

Read the local journal backup files for each day in the range
(Monday through Sunday). The files are at:

```
reports/journal/{year}/{month:02d}/{M}-{D}.md
```

For each day, check if the file exists. Read all that exist.
If no local backup exists at all, run `/journal sync` first.

If fewer than 3 days have entries, warn the user that the summary
may be sparse.

### Step 3 — Extract and group by product/mission

Scan all daily entries and dynamically identify product/mission
groupings. Look for recurring project names, product names, and
themes across the week's entries.

Common groupings (detect dynamically, don't hardcode):
- Product names: SAVER, Xclops NG, VIPLink, VIPOnly/LUMI, Forge,
  OrbitVision, FoveaCTL, Commander, etc.
- Mission names: Haven-1, QC Pro, IQT, Shield Space, etc.
- Infrastructure: Jenkins, Gitea, BSP, devcontainer, build system
- Meetings & coordination
- Admin / misc

**How to detect groupings:**
1. Scan all daily content for known repo names (from workspace),
   product names, mission names, and ClickUp ticket prefixes
2. Also look for markdown headers in daily entries — they often
   indicate project groupings
3. Cluster related items under the most descriptive label
4. Merge small groups (1-2 items) into a broader category or "Other"
5. Order groups by volume of activity (most active first)

### Step 4 — Synthesize the summary

Write a comprehensive week-in-review that:

- Opens with a 2-4 sentence overview of the week's main themes
- Groups work into sections by product/mission (detected in Step 3)
- Within each section, summarizes what was accomplished — focus on
  outcomes but include all notable items, not just the biggest ones
- Mentions key people collaborated with
- Notes significant deliverables, PRs merged, milestones hit
- Includes minor items (small fixes, package changes, misc admin)
  in appropriate sections or a Misc section at the end
- Keeps total length to 300-800 words
- Uses past tense, first person implied

**Summarize, don't enumerate commits.** For example:
- BAD: "Committed `abc123`, `def456`, `ghi789` to add camera support"
- GOOD: "Built out Ximea camera integration for Xclops NG, including
  the GStreamer plugin, unit tests, and thread safety fixes"

**But do include all work items.** Don't drop minor fixes, small
package changes, or admin items. Group them logically — either under
the relevant product section or under a Misc section at the end.

**Preserve key references.** Even though this is a summary, include:
- ClickUp ticket links for significant items: `[SW-XXXX](url)`
- Merge commit hashes for notable merges: `` `e56787d7` ``
- Don't include every individual commit hash — only merges and
  significant standalone commits

**Section format:**

```markdown
## Product/Mission Name
- Summary bullet about what was accomplished
- Another bullet about progress or outcome
- Notable: [SW-XXXX](url), merged `hash`
```

**Section order:**
1. Main engineering work (largest sections first)
2. Meetings & collaboration
3. Infrastructure / tooling
4. Admin / misc (only if notable)

Skip sections with no activity — don't mention their absence.

### Step 5 — Output

#### Preview mode (default)

Write the summary to `reports/weekly-review-preview.md` using the
Write tool. Display it in the conversation. Ask the user:

> Ready to publish to ClickUp as "Week of M/D-M/D"? (yes/no)

If yes, proceed to publish. If no, ask what to change.

#### Publish mode

1. Find the parent month page in ClickUp for the Sunday date.
   Look up `_index.json` for month pages, or list pages to find the
   correct `MM - Mon` page under the year.

2. Check if a "Week of M/D-M/D" page already exists:
   - If yes, read existing content and replace it
   - If no, create a new page

3. Create or update the page.

   **Important:** The `clickup` CLI `--parent-page-id` flag does not
   correctly place pages under a parent. Use the ClickUp v3 REST API
   directly via `curl` to create pages with a parent:

   ```bash
   CLICKUP_TOKEN=$(python3 -c "import json; print(json.load(open('$HOME/.config/clickup-cli-nodejs/config.json'))['profiles']['default']['token'])")

   # Create new page under the correct parent
   curl -s -X POST \
     "https://api.clickup.com/api/v3/workspaces/20557679/docs/kkbvf-4151/pages" \
     -H "Authorization: $CLICKUP_TOKEN" \
     -H "Content-Type: application/json" \
     -d "$(python3 -c "
   import json
   with open('/tmp/weekly-review.md') as f:
       content = f.read()
   print(json.dumps({
       'name': 'Week of <M/D-M/D>',
       'parent_page_id': '<month_page_id>',
       'content': content
   }))
   ")"

   # Or update existing page (CLI works fine for updates)
   clickup doc page-update \
     --doc-id kkbvf-4151 \
     --page-id <page_id> \
     --content "$(cat /tmp/weekly-review.md)"
   ```

4. Also save a local copy at:
   ```
   reports/journal/{year}/{month:02d}/week-{M}-{D}-{M}-{D}.md
   ```

### Step 6 — Report to user

After publishing, display:
- Date range covered
- Number of daily entries read
- Product/mission groupings found
- ClickUp page link (if published)

---

## Edge Cases

**No local backup exists**: Run `/journal sync` first, then proceed.

**Missing daily entries**: Summarize whatever days are available.
If zero entries found, tell the user and stop.

**Week spans two months**: The page goes under the month of the
Sunday (end of week). Read journal files from both months.

**Week spans two years**: Same approach — page goes under the
Sunday's year/month.

**User provides additional context**: Incorporate it into the
summary prominently.

**Page already exists in ClickUp**: Replace its content (this is a
regenerated summary).

---

## Tone & Style

- Match the daily journal's informal, technical shorthand
- Factual and concise — no editorializing
- Bullet points > paragraphs; prose only for the opening overview
- No blank lines before or after headings (compact formatting)
- First names only for colleagues
- Higher-level than daily summaries — focus on the narrative arc
  of the week, not the daily minutiae
