---
name: clickup-timesheet
description: >
  Generate and submit time entries to ClickUp based on sprint tickets,
  git commit history, and the user's typical work schedule. Use this
  skill whenever the user asks to fill out their timesheet, log time
  entries, backfill hours, update their ClickUp time tracking, or
  generate a timesheet for a given period. Also trigger when the user
  says things like "fill my timesheet", "log my hours", "I need to
  submit time entries", "backfill time for last month", "update my
  ClickUp hours", or any request involving ClickUp time tracking tied
  to sprint tickets or git activity. Even if the user just says
  "timesheet" or "time entries", use this skill.
user-invokable: true
allowed-tools: Bash, Read, Write, Grep, Glob, Agent
---

# ClickUp Timesheet Generator

Generate realistic time entries for ClickUp by cross-referencing sprint
tickets, git commit history, and the user's stated work patterns, then
submit them via the ClickUp CLI.

All ClickUp operations use the `clickup` CLI with `--format json` for
machine-readable output. Parse JSON with `jq` or Python.

## Overview

The goal is to turn a firehose of sprint tickets and git commits into
accurate time entries without the user doing manual data entry. The
skill gathers evidence, generates a plan, and submits it — but only
after the user has reviewed and approved a spreadsheet of the proposed
entries.

**Critical rule: Always present a spreadsheet for user review before
submitting any time entries to ClickUp. Never auto-submit.**

## Data Sources

Both inputs are gathered automatically — no user action needed:

1. **ClickUp sprint tickets** (automatic) — Tasks assigned to the
   user, closed within the target date range. Provides ticket IDs,
   names, story points, sprint membership, and close dates.
2. **Git commit history** (automatic) — Collected by running
   `repos.sh changelog` across all workspace repos. Branch names
   containing ticket IDs (e.g.,
   `feature/SW-4542-Xclops-Video-recording`) link commits to tickets.
   Commit timestamps show which days had activity on which tickets.

## Hardcoded Work Pattern Defaults

These are always used. Do not ask the user about them:

| Parameter | Value |
|-----------|-------|
| Weekly hour target | 55-70h, median 60h |
| Mon-Thu hours | ~10h per day |
| Fri hours | ~8h per day |
| Evening work | Sometimes 9pm-12am |
| Weekend work | Only on days with ticket-specific git commits |
| Max tickets per day | 3 |
| Hour granularity | Whole hours only |
| Max entries per single-day ticket | 2 |
| Ticket filter | Only SW-* sprint tickets |

## CLI Reference

All ClickUp operations use the `clickup` CLI. Always pass `--format json`
for machine-readable output.

### Get current user ID

```bash
clickup workspace members --format json | jq '.[] | select(.user.username == "<username>") | .user.id'
```

Or get all members and match by name/email.

### Search tasks

```bash
clickup task search \
  --assignee <user_id> \
  --include-closed \
  --space-id <space_id> \
  --order-by due_date \
  --format json
```

Use `--page 0`, `--page 1`, etc. to paginate (keep going until results
are empty or fewer than a full page).

### Get task details

```bash
clickup task get <task_id> --format json
```

Works with both internal IDs and custom IDs (e.g., `SW-1234`).

### List time entries (workspace-wide)

```bash
clickup time list \
  --start "YYYY-MM-DD" \
  --end "YYYY-MM-DD" \
  --assignee <user_id> \
  --format json
```

### List time entries (per task)

```bash
clickup time list --task-id <task_id> --format json
```

### Create a time entry

```bash
clickup time create \
  --task-id <task_id> \
  --start "<unix_ms_or_date_string>" \
  --duration <milliseconds> \
  --format json
```

Duration is in **milliseconds** (1 hour = 3600000).
Start can be a Unix timestamp in ms or an ISO 8601 date string.

## Workflow

### Step 1 — Collect the git log

Infer the date range from the user's request. Phrases like "this
month", "for March", "last sprint", "backfill for April" all contain
the date range — do NOT ask the user to confirm or clarify it. If
no time period is mentioned at all, default to the current month.

Get the git author name automatically:

```bash
git config user.name
```

Then run the changelog command directly to collect commit history
across all workspace repos:

```bash
bash /workspaces/trl-work/trl-work/tools/repos.sh changelog YYYY-MM-DD YYYY-MM-DD
```

Save the output to a variable for parsing in Step 3.

Do NOT ask about weekly hours, daily schedule, evening work,
weekend preferences, max tickets, or any other work pattern
parameters. Use the hardcoded defaults above.

### Step 2 — Fetch ClickUp data and existing time entries

Get the user's ClickUp member ID:

```bash
clickup workspace members --format json
```

Parse the JSON to find the current user's `user.id` (match by name
or email). Store this as `USER_ID`.

Search for tasks assigned to the user, closed within the date range:

```bash
clickup task search \
  --assignee $USER_ID \
  --include-closed \
  --order-by due_date \
  --format json \
  --page 0
```

Paginate through all results (page 0, 1, 2, ...) until the result set
is empty. Also search for in-progress tasks:

```bash
clickup task search \
  --assignee $USER_ID \
  --status "in progress" \
  --status "Open" \
  --format json
```

For each task, note: `id`, `custom_id`, `name`, `points`,
`date_done`, and `list.name` (sprint name).

Fetch ALL existing time entries in the date range for this user:

```bash
clickup time list \
  --start "YYYY-MM-DD" \
  --end "YYYY-MM-DD" \
  --assignee $USER_ID \
  --format json
```

Build an inventory of what already exists:
- **Per-ticket totals**: How many hours are already logged against
  each ticket
- **Per-day totals**: How many hours are already logged on each day
- **Per-day ticket list**: Which tickets already have entries on
  each day (counts toward the max-tickets-per-day limit)

This inventory is critical input to Step 4. Existing entries are
NOT duplicated or overwritten — they reduce what the generator needs
to produce.

### Step 3 — Parse git commit history

Parse the changelog output from Step 1 to extract:
- Only the user's commits (filter by author name from `git config`)
- Date and time of each commit
- Repository name (the repo label printed by `repos.sh`)
- Ticket IDs from branch names or commit messages
  (regex: `(SW-\d+|MIS-\d+|PROJ-\d+|OPS-\d+)`)

Build two maps:
- **date -> tickets**: Which tickets had commits on each day
- **ticket -> dates**: Which days each ticket was worked on

Treat commit dates as *evidence of activity on or near that date*.
Commits may consolidate work from previous days, so spread hours
across the days leading up to the commit, not only the commit day.

### Step 4 — Generate the timesheet plan

Use the existing time entry inventory from Step 2 to avoid
duplicating work. The generator must account for what's already
logged before producing new entries.

Write a Python script that:

1. **Assigns total hours per ticket** based on story points:
   - 2 pts -> 5-8h, 3 pts -> 8-12h, 5 pts -> 13-18h, 8 pts -> 18-24h
   - Scale this mapping up or down to hit the user's weekly targets
   - **Subtract existing hours**: If a ticket already has N hours
     logged, reduce the target by N. If a ticket already meets or
     exceeds its target, skip it entirely.

2. **Builds a work day calendar** with per-day hour budgets:
   - Weekdays get the user's stated daily hours
   - Weekends only appear if the user requested it AND there were
     ticket-specific commits on that day
   - Apply randomness (+/-1-2h) to avoid a robotic pattern
   - **Subtract existing daily hours**: If a day already has N hours
     logged, reduce that day's remaining budget by N.
   - **Account for existing ticket slots**: If a day already has K
     distinct tickets logged, only (max_tickets_per_day - K) new
     tickets can be added to that day.

3. **Assigns tickets to days** using git evidence:
   - For each ticket, the work window runs from (first git commit
     minus 1-3 days) through (ClickUp close date or last commit)
   - Prefer days with actual git commits (score: 10), days just before
     commits (score: 5), other days in window (score: 1)
   - Use weighted random selection to pick 2-4 days per ticket
   - Respect max-tickets-per-day constraint (including existing entries)

4. **Generates time entries** with start times:
   - Morning block starts 8-9am (weekdays) or 9-11am (weekends)
   - 1h gaps between different tickets (lunch/breaks)
   - If work pushes past 6pm, schedule overflow as evening entries
     (9pm-midnight)
   - Whole hours only (or whatever granularity the user requested)
   - For tickets appearing on only 1 day, max 2 entries

5. **Validates all constraints** before presenting:
   - Whole hours (no fractional)
   - Max N tickets per day
   - Max 2 entries for single-day tickets
   - No entries outside the user's stated work hours
   - Weekly totals near the target

### Step 5 — Present for review (REQUIRED before any submission)

**This step is mandatory. Never skip it. Never submit entries without
explicit user approval.**

**Important: Display the timesheet as text output directly in the
conversation — do NOT only print it inside a Bash tool call.** Tool
call output may be hidden from the user. After generating the data
(via Python/Bash), reproduce the table and summary as regular text
in your response so the user can actually see it.

#### Entries table

Display a markdown table with columns: Date, Day, Start, End, Hours,
Ticket, Name, Sprint. Group rows by date with a day-total row after
each day's entries. Mark weekend and evening entries.

#### Summary

Below the table, show:
- **Existing entries**: count and total hours already logged
- **New entries**: count and total hours to submit
- **Combined total**: existing + new

#### Daily breakdown

A short table: Date, Day, Hours, Budget.

#### Per-ticket breakdown

A short table: Ticket, Name, Hours, Target, Status.

Flag any issues:
- Weekly totals significantly above or below target
- Empty weekdays with no entries
- Tickets that couldn't be scheduled and why
- Tickets skipped because they already had enough hours

Then explicitly ask the user whether to proceed. Do not proceed until
the user says yes. If the user requests changes (move hours, swap
days, add/remove tickets, adjust totals), regenerate the plan and
present again for another round of review.

### Step 6 — Submit to ClickUp (only after Step 5 approval)

Only after the user has reviewed the spreadsheet and explicitly
approved it, iterate through the entries and submit via the CLI:

```bash
clickup time create \
  --task-id "<task_id_or_custom_id>" \
  --start "<unix_ms_timestamp>" \
  --duration <milliseconds> \
  --format json
```

Convert hours to milliseconds: `hours * 3600000`.
Convert start times to Unix ms: use Python or `date +%s%3N`.

Report progress as you go (e.g., "Submitted 15/63 entries..."). If
any entry fails, log the failure details and continue with the rest.
After all entries are attempted, report successes and failures.

### Step 7 — Verify

After submission, call `clickup time list` for the date range to
confirm all entries were created:

```bash
clickup time list \
  --start "YYYY-MM-DD" \
  --end "YYYY-MM-DD" \
  --assignee $USER_ID \
  --format json
```

Compare the expected count and total hours against what was actually
submitted. Report any discrepancies.

## Edge Cases

- **Duplicate prevention**: Always check for existing time entries in
  the date range before generating new ones. Warn the user if entries
  already exist.
- **No git log provided**: Fall back to spreading hours based on
  ClickUp close dates and story points alone. Inform the user that
  dates will be less accurate without git data.
- **Tickets without points**: Default to 3 points (medium effort).
- **In-progress tickets**: Assign work to the last week of the date
  range.
- **Overlapping entries**: Ensure no two entries on the same day
  overlap in time. Leave gaps between entries.
- **API rate limits**: Add brief pauses between API calls if
  submitting many entries.

## Important Notes

- This skill only logs time against sprint tickets (typically SW-*
  prefix). Infrastructure work, CI/CD maintenance, and similar tasks
  without sprint tickets are excluded unless the user explicitly
  provides a ticket to use.
- Always present the plan for review before submitting. Never
  auto-submit without user confirmation.
- Git commit timestamps may not reflect the actual work day. Treat
  them as signals, not ground truth.
