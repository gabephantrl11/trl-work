---
name: project-report
description: >
  Generate a comprehensive project report by searching Slack, ClickUp, Gmail,
  Google Drive, and local git repos for all information about a given project
  or product. Outputs a markdown report to reports/. Use this skill when the
  user asks to create a project report, project summary, product overview,
  or says things like "report on X", "give me a picture of X project",
  "summarize the X project", "what do we know about X", or "write up a
  report on X".
user-invokable: true
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Agent
---

# Project Report Generator

Search across all company data sources for information about a specific
project or product, then synthesize a comprehensive markdown report to
`reports/`.

## Invocation

```
/project-report <project-name>
```

If no project name is provided, ask the user which project to report on.

## Data Sources

Search **all** of the following for the project name (and known aliases):

| Source | What to look for |
|--------|-----------------|
| **ClickUp** | Tasks, docs, milestones across all spaces (Software, Missions, Gov Contracts, Rocks, Mechanical, Ops, BD) |
| **Slack** | Messages in project channels, team channels, DMs; shared files |
| **Gmail** | Calendar invites, document shares, GitHub notifications, program updates |
| **Google Drive** | Documents, spreadsheets, presentations, uploaded files via `gws` CLI |
| **Google Calendar** | Meetings, reviews, milestones via `gws` CLI |
| **Git** | Commit history, branches, PRs in the local repo (if one exists under `/workspaces/trl-work/`) |
| **Local repo** | README, CLAUDE.md, architecture, build system |

## Workflow

### Step 1 — Identify the project and aliases

Determine the project name and any known aliases or prior names. For
example, OrbitVision was previously called TelescopeCtrl. Search for
all variants.

### Step 2 — Search all sources in parallel

Launch parallel searches to maximize speed:

1. **ClickUp search** — Search for the project name using `clickup_search`.
   Paginate with cursor if more results exist. Also search with alternate
   spellings (e.g. "OrbitVision" and "Orbit Vision").
2. **Slack messages** — Use `slack_search_public_and_private` for messages
   mentioning the project. Use `content_types="files"` in a second search
   to find shared files.
3. **Gmail** — Use `gmail_search_messages` for emails about the project.
4. **Google Drive** — Search for files using `gws` CLI (see reference below).
   Use both `name contains` and `fullText contains` queries to catch files
   that mention the project inside their content.
5. **Google Calendar** — Search for meetings/events using `gws` CLI.
6. **Local repo** — Check if a matching repo exists under
   `/workspaces/trl-work/`. If so, read README.md and CLAUDE.md, run
   `git log --oneline --all`, and inspect the project structure.

### Step 3 — Deep-dive on key results

For important items found in Step 2:

- **ClickUp tasks**: Use `clickup_get_task` with `detail_level=summary`
  on key milestone and project-type tasks to get dates, assignees, and
  descriptions.
- **Slack channels**: If a dedicated project channel exists, use
  `slack_read_channel` to read the full history for richer context.
- **Google Docs/Sheets**: For key documents found on Drive, optionally
  read their content using `gws docs documents get` or
  `gws sheets spreadsheets get` to extract relevant details.
- **Gmail threads**: Read key emails for details on meetings, shared
  documents, and schedules.

### Step 4 — Write the report

Write a markdown report to `reports/<project-name-kebab>-project-report.md`.

## Report Structure

The report must include all of the following sections. Omit a section
only if there is genuinely no data for it.

### 1. Executive Summary
2-3 paragraph overview: what the project is, its purpose, current phase,
and key upcoming milestone.

### 2. Project Origins & History
Chronological table of key milestones from earliest to most recent.
Include dates, events, and who was involved.

### 3. Architecture & Components
Technical overview of the system: components, technologies, hardware,
key capabilities. Pull from README, code structure, and Slack discussions.

### 4. Team & Stakeholders
Table of people involved and their roles, derived from ClickUp assignees,
Slack participants, and email recipients.

### 5. Schedule & Milestones
Three sub-tables:
- **Upcoming** — Future milestones with target dates and status
- **Completed** — Recently completed milestones
- **Long-Horizon** — Items further out or ongoing

### 6. ClickUp Tickets
Group tickets by ClickUp space/folder with tables containing:
ID (linked), Name, Status, Assignee.

### 7. Key Documents & Resources
All discovered documents and resources, organized by source:
- SharePoint / Google Drive documents (with links)
- Slack channels (with archive links)
- GitHub repos (with links)
- Other external resources

### 8. Current Status & Open Actions
The most recent actionable items — what's happening right now, who
owns what, and what's next. Link to the source Slack message or
ClickUp task.

### 9. Open Risks & Issues
Table of risks and blockers identified from discussions and ticket
statuses.

### 10. Partner & Customer Engagement
Table of external partners/customers, what the engagement is, and
current status. Only include if relevant.

### 11. Software Development Summary
Brief narrative of the codebase evolution, recent development activity,
and current state. Only include if a software repo exists.

## Linking Rules

Every cited resource must have a clickable link:

| Resource | Link format |
|----------|------------|
| ClickUp task | `[SW-1234](https://app.clickup.com/t/<task_id>)` |
| Slack channel | `[#channel-name](https://trl11.slack.com/archives/<channel_id>)` |
| Slack message | `[Slack post](https://trl11.slack.com/archives/<channel_id>/p<message_ts_no_dot>)` |
| SharePoint doc | Full SharePoint URL as discovered from Slack/email |
| Google Doc/Sheet/Slide | `webViewLink` from `gws drive files list` result |
| GitHub repo | `[org/repo](https://github.com/org/repo)` |
| External URL | Use the URL as-is |

## Important Notes

- Search for **all known aliases** of the project (prior names, abbreviations)
- Run searches in **parallel** to minimize latency
- Include **dates** on everything — convert Unix timestamps to human-readable
- The report should be **self-contained** and readable without clicking links
- Prefer **facts from primary sources** (ClickUp, git) over secondhand summaries
- When Slack messages provide key context not available elsewhere, quote or
  paraphrase them
- Do not fabricate information — if a section has no data, note that
- After writing, provide a brief summary to the user: file path, sections
  covered, key findings

## gws CLI Reference

The `gws` CLI provides direct access to Google Workspace APIs. Use it via
Bash for Drive, Calendar, Docs, Sheets, and Slides searches.

### Search Google Drive files

```bash
# Search by file name
gws drive files list --params '{
  "q": "name contains '\''PROJECT_NAME'\''",
  "pageSize": 20,
  "fields": "files(id,name,mimeType,webViewLink,modifiedTime,owners)"
}'

# Search inside file content (full-text)
gws drive files list --params '{
  "q": "fullText contains '\''PROJECT_NAME'\''",
  "pageSize": 20,
  "fields": "files(id,name,mimeType,webViewLink,modifiedTime,owners)"
}'
```

The `webViewLink` field is the clickable URL to include in the report.
Filter out irrelevant results by checking `name` and `mimeType`.

### Search Google Calendar events

```bash
# Search for meetings about the project
gws calendar events list --params '{
  "calendarId": "primary",
  "q": "PROJECT_NAME",
  "timeMin": "2025-01-01T00:00:00Z",
  "maxResults": 20,
  "singleEvents": true,
  "orderBy": "startTime"
}'
```

### Read Google Doc content

```bash
gws docs documents get --params '{"documentId": "DOC_ID"}'
```

### Read spreadsheet data

```bash
gws sheets spreadsheets get --params '{
  "spreadsheetId": "SHEET_ID",
  "includeGridData": true
}'
```

### Read presentation slides

```bash
gws slides presentations get --params '{"presentationId": "PRES_ID"}'
```

