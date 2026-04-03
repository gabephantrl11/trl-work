---
name: daily-journal-summary
description: >
  Summarize everything Gabe did today and append it to today's journal entry
  in ClickUp (Gabe's Space > Journal). Use this skill whenever the user asks
  to summarize their day, log what they did today, update their journal with
  today's work, write an end-of-day summary, or says things like "wrap up my
  day", "add to my journal", "summarize today", "EOD summary", "what did I do
  today", or "log today's work". Always use this skill for any end-of-day or
  daily recap request that should be written to the ClickUp journal.
user-invokable: true
allowed-tools: Bash, Read, Agent, mcp__claude_ai_ClickUp__clickup_resolve_assignees, mcp__claude_ai_ClickUp__clickup_search, mcp__claude_ai_ClickUp__clickup_list_document_pages, mcp__claude_ai_ClickUp__clickup_get_document_pages, mcp__claude_ai_ClickUp__clickup_update_document_page, mcp__claude_ai_ClickUp__clickup_create_document_page, mcp__claude_ai_ClickUp__clickup_get_time_entries, mcp__claude_ai_Slack__slack_search_public_and_private, mcp__claude_ai_Gmail__gmail_search_messages, mcp__claude_ai_Google_Calendar__gcal_list_events
---

# Daily Journal Summary Skill

Gather signals from all connected sources, synthesize a concise end-of-day
summary, and append it to today's journal page in Gabe's ClickUp Journal doc.

## Key Facts (hardcoded — do not ask)

| Field | Value |
|-------|-------|
| Journal doc ID | `kkbvf-4151` |
| Journal doc location | Gabe's Space in ClickUp |
| Page naming convention | `M/D` (e.g. `4/3` for April 3) |
| Page hierarchy | Journal → YYYY → MM - Mon → M/D |
| Gabe's ClickUp user | resolve via `clickup_resolve_assignees(["me"])` |
| Summary header | `# End of Day Summary` |

---

## Workflow

### Step 1 — Find today's journal page

List all pages in the Journal doc:
```
clickup_list_document_pages(document_id="kkbvf-4151")
```

Find the page whose `name` matches today's date in `M/D` format (e.g. `4/3`
for April 3). If no page exists yet for today, note that — you'll create one
later (see Edge Cases).

Read the current page content:
```
clickup_get_document_pages(document_id="kkbvf-4151", page_ids=["<page_id>"])
```

Store the full existing content — you'll need it when writing back, because
`clickup_update_document_page` **replaces** the entire page.

### Step 2 — Gather today's activity signals

Pull from all available sources in parallel where possible. For every item
collected, **always capture the direct URL or deep link** — this is required
for Step 3.

**ClickUp tasks** — tasks updated or closed today assigned to Gabe:
```
clickup_search(
  filters={
    assignees: [<gabe_user_id>],
    asset_types: ["task"],
    created_date_from: "YYYY-MM-DD",  # today
  },
  sort=[{field: "updated_at", direction: "desc"}]
)
```
For each task, capture: `custom_id` (e.g. `SW-4542`), `name`, `url`
(format: `https://app.clickup.com/t/<task_id>`), and `status`.

Also fetch time entries logged today via `clickup_get_time_entries` for
today's date range.

**Slack** — search recent messages sent by Gabe today, and any threads
he participated in heavily. Use `slack_search_public_and_private` with a
date filter for today. For each result, capture the `permalink` URL and
channel name.

**Gmail** — emails sent today. Use `gmail_search_messages` with
`after:<today_date>` filter. Capture subject and any linked URLs if relevant.
Gmail messages don't have deep links to include, so summarize by subject only.

**Google Calendar** — events today. Use `gcal_list_events` for today's
date range. Capture event title, attendees, and the `htmlLink` URL for
each event.

**Google Drive** — documents created or modified today. Use the Drive
search tool with `modifiedTime > '<today_start>'`. Capture file name and
`webViewLink` (the direct URL to open the file in Drive/Docs/Sheets).

**Git commits** — commits authored by Gabe today across all workspace repos.
First fetch all remotes so the log includes anything pushed from other machines:
```bash
for repo in */; do
  [ -d "$repo/.git" ] && git -C "$repo" fetch --all 2>&1
done
```
Then scan for today's commits:
```bash
for repo in */; do
  if [ -d "$repo/.git" ]; then
    commits=$(git -C "$repo" log --oneline --after="<today>T00:00:00" --before="<tomorrow>T00:00:00" --author="gabe\|Gabe" 2>/dev/null)
    if [ -n "$commits" ]; then echo "=== $repo ==="; echo "$commits"; fi
  fi
done
```
For each commit, capture the repo name, short hash, and subject line. Group
by repo in the summary and briefly describe what the commits accomplished
(e.g. "merged VimbaX upgrade into dev, installed tudat resources into BSP").

Do not ask Gabe to provide any of this — gather it automatically.

### Step 3 — Synthesize the summary

Write a concise, narrative end-of-day summary that:

- Opens with a 1–3 sentence "headline" capturing the day's main theme
- Groups work into logical sections (e.g. by project: SAVER, Xclops NG,
  IQT, infrastructure, meetings, etc.)
- Within each section, uses short bullet points — what was done, any
  blockers, outcomes, or next steps if obvious
- Mentions key people interacted with (meetings, Slack threads, reviews)
- Notes any deliverables produced, PRs opened/merged, tickets closed
- Keeps total length to roughly 150–400 words — enough to be useful
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

### Step 4 — Append to the journal page

Construct the updated page content:

```
<existing page content>
# End of Day Summary
*<Today's date, written out, e.g. "Friday, April 3, 2026">*
<synthesized summary — no blank lines before or after headings>
```

Write it back with:
```
clickup_update_document_page(
  document_id="kkbvf-4151",
  page_id="<today_page_id>",
  content="<full updated content>",
  content_format="text/md"
)
```

**Important**: Preserve all existing content verbatim. Only append — never
modify or reformat what's already there.

### Step 5 — Confirm

Tell Gabe:
- That the summary was appended to today's journal entry
- Provide a brief 2–3 line preview of what was written
- Offer to adjust tone, length, or add/remove anything

---

## Edge Cases

**No journal page exists for today**: Create one first:
```
clickup_create_document_page(
  document_id="kkbvf-4151",
  name="<M/D>",
  parent_page_id="<current month page id>",
  content="",
  content_format="text/md"
)
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
