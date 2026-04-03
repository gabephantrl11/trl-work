---
name: missions-summary
description: >
  Update the "2026 Missions & Projects Summary" ClickUp document with
  reference links to tickets, a chronological timeline sorted by due
  date, and a backlog section. Use this skill when the user asks to
  update, refresh, or regenerate the missions summary doc, sync the
  missions doc with ClickUp, or asks about updating the missions and
  projects overview. Also trigger for phrases like "update the missions
  doc", "refresh the summary", "sync missions summary", or
  "regenerate the project summary".
user-invokable: true
allowed-tools: Bash, Read, Agent, mcp__claude_ai_ClickUp__clickup_get_workspace_hierarchy, mcp__claude_ai_ClickUp__clickup_filter_tasks, mcp__claude_ai_ClickUp__clickup_search, mcp__claude_ai_ClickUp__clickup_list_document_pages, mcp__claude_ai_ClickUp__clickup_get_document_pages, mcp__claude_ai_ClickUp__clickup_update_document_page, mcp__claude_ai_ClickUp__clickup_create_document_page
---

# Missions & Projects Summary Updater

Update the ClickUp document "2026 Missions & Projects Summary" by
pulling live ticket data from the Missions and Projects spaces,
adding reference links, building a chronological timeline, and
compiling a backlog section.

## Target Document

- **Document ID:** `kkbvf-58711`
- **Page ID:** `kkbvf-48331`
- **URL:** https://app.clickup.com/20557679/v/dc/kkbvf-58711/kkbvf-48331
- **Location:** Gabe's Space (workspace 20557679)

## Source Spaces

| Space | ID | Content |
|-------|----|---------|
| Missions | `32297811` | Customer missions with folders per mission/customer |
| Projects | `90112012593` | Product planning, master projects list, VIP products |

## Workflow

### Step 1 — Fetch all tasks from both spaces

Use `clickup_filter_tasks` to pull tasks from both spaces. Paginate
through all results (page 0, 1, 2, ...) until the count returned is
less than 100. Use these parameters:

```
space_ids: ["32297811"]  (Missions)
space_ids: ["90112012593"]  (Projects)
order_by: "due_date"
subtasks: false
```

For each task, capture: `id`, `custom_id`, `name`, `status`, `url`,
`priority`, `assignees`, `tags`, `due_date`, `list.name`.

### Step 2 — Read the current document

Use `clickup_get_document_pages` to read page `kkbvf-48331` from
document `kkbvf-58711` with `content_format: "text/md"`.

Review the existing structure to understand what sections exist and
what content needs updating.

### Step 3 — Convert timestamps and organize data

Convert all `due_date` timestamps (milliseconds since epoch) to
human-readable dates. Use Python via Bash:

```python
from datetime import datetime, timezone
dt = datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc)
date_str = dt.strftime("%Y-%m-%d")
```

Organize tasks into:

1. **By mission/customer** — Group Missions space tasks by their
   folder (Haven-1, Exlabs, QC Pro, MI:4, Shield Space, etc.)
2. **By due date** — Sort all tasks with due dates chronologically
   for the timeline
3. **Backlog** — Collect tasks with status "backlog", "idle", or
   "blocked", or tasks with no due date

### Step 4 — Build the updated document

The document must contain these sections in order:

#### Section 1: Header
```markdown
# 2026 Missions & Projects Summary

_Generated: {today's date} — Updated with ticket references, timeline, and backlog_

This document summarizes all active missions, customers, and key
projects tracked in the **Missions** and **Projects** ClickUp spaces
for 2026.
```

#### Section 2: Mission Timeline (Sorted by Key Milestones)

A chronological timeline broken into monthly subsections. Each month
is a table with columns: Date, Mission, Milestone, Ticket.

- Include only significant milestones (deliveries, reviews, testing
  campaigns, design starts, reports — not routine tasks)
- The Ticket column uses the format `[MIS-XXXX](url)` or
  `[PROJ-XXXX](url)` with the full ClickUp task URL
- Sort entries within each month by date ascending
- Group months as `### April 2026`, `### May 2026`, etc.
- Include a `### 2027+` section if milestones extend beyond 2026

Select milestones by prioritizing tasks that match these patterns:
- Contract milestones, deliveries, need-by dates
- Design reviews (PDR, CDR, SRR)
- Testing campaigns (qualification, acceptance, environmental, ATP)
- FM/EM/DM builds, assemblies, checkouts
- Final reports, shipping dates
- Software releases
- Key procurement deadlines
- Urgent or high-priority items

Limit to ~8-15 entries per month to keep the timeline scannable.

#### Section 3: Missions Space — By Customer / Mission

Keep the existing numbered mission structure (1. VAST — Haven-1,
2. Exlabs, 3. QC Pro, etc.). For each mission:

- Preserve the Customer, Status, and Key Activities format
- Add `[MIS-XXXX](url)` reference links after each activity line
- Update dates to match current ticket due dates
- Update statuses to match current ticket statuses
- Add any new tasks that weren't in the previous version
- Remove tasks that have been deleted or are no longer relevant
- Note cancelled tasks as "Cancelled" rather than removing them

The mission ordering should follow the existing document's numbering
unless a new mission/customer has been added (append it).

#### Section 4: Projects Space — Key Initiatives

Organize into these subsections with tables:
- Product Planning & Development
- CV Algorithms (VIPOnly)
- Business Development & Proposals
- Software Releases
- Compliance & Quality
- Other Notable Projects

Each table should include a Ticket column with `[PROJ-XXXX](url)`.

#### Section 5: Customer Summary

A summary table with columns: Customer, Missions/Programs, Status,
Key Tickets. The Key Tickets column should have 1-2 of the most
important ticket links per customer.

#### Section 6: Backlog

Two tables:
- **Missions Backlog** — Columns: Item, Mission, Status, Ticket
- **Projects Backlog** — Columns: Item, Category, Status, Ticket

Include tasks that are blocked, backlog, idle, or have no near-term
due date and are not actively being worked.

### Step 5 — Update the document

Use `clickup_update_document_page` to replace the page content:

```
document_id: "kkbvf-58711"
page_id: "kkbvf-48331"
content_format: "text/md"
content: <full markdown content>
```

**Important:** This tool REPLACES the entire page content. Always
include the complete document, not just changed sections.

If the update fails with a gateway error (502), retry once after a
brief pause.

### Step 6 — Report to user

After updating, provide a summary:
- Number of missions covered
- Number of tasks linked
- Timeline date range
- Number of backlog items
- Link to the updated document

## Reference: Folder-to-Mission Mapping

These are the folders in the Missions space and which mission they
correspond to:

| Folder | Mission |
|--------|---------|
| Haven-1 | VAST — Haven-1 |
| Exlabs | Exlabs |
| QC Pro (X-Clops) | QC Pro — Obruta |
| MI:4 Sierra Space (Bi-Clops) | MI:4 Sierra Space |
| Shield Space (Biclops) | Shield Space |
| Orbit Vision (Ground Segment) | Orbit Vision |
| Otter-1 (Starfish, HC) | Starfish Space — Otter-1 |
| SO #82 & #83: Starfish Space | Starfish Space — SO #82/#83 |
| Reflect Orbital (QTY: 40 Estimate) | Reflect Orbital (Bulk) |
| SO #43: Reflect Orbital | Reflect Orbital — SO #43 |
| SO #63: Reflect Orbital | Reflect Orbital — SO #63 |
| Giga-HANS | Giga-HANS |
| SSPICY | SSPICY |
| Portal MI:3 (POTs & SAVER) | Portal MI:3 |
| K2 | K2 |
| MI:2 (T-12) | MI:2 (T-12) |
| Planning Projects | Astranis (Planning) |
| OrbitAid | OrbitAid |
| ORDERS (OTS) | OTS Orders |

## Important Notes

- Always use full ClickUp task URLs for reference links, in the
  format `[CUSTOM-ID](https://app.clickup.com/t/TASK_ID)`
- The document should be self-contained and readable without
  clicking any links
- Preserve the existing mission numbering and structure where
  possible for continuity
- Do not include subtasks — only top-level tasks
- Use exact dates (e.g., "Jun 27") in the timeline, not approximate
  months
- When a task has been cancelled, note it as cancelled rather than
  omitting it
- The backlog section helps leadership see what's queued up beyond
  the active timeline
