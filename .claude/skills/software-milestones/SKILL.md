---
name: software-milestones
description: >
  Generate a software milestones timeline from ClickUp tasks tagged
  with SW in the Teams custom field. Outputs a markdown file to
  reports/. Use this skill when the user asks to generate, update, or
  refresh the software milestones report, or says things like "SW
  milestones", "software timeline", "what's coming up for SW", or
  "update the SW milestones doc".
user-invokable: true
allowed-tools: Bash, Read, Write, Agent
---

# Software Milestones Generator

Pull tasks tagged with **SW** in the Teams custom field from all
ClickUp spaces, build a chronological timeline with overdue/upcoming
markers, and write the result to `reports/software-milestones.md`.

All ClickUp operations use the `clickup` CLI with `--format json`.
Parse JSON with `jq` or Python.

## Output

```
reports/software-milestones.md
```

Create `reports/` if it does not exist. Overwrite on regeneration.

## ClickUp Reference IDs

| Item | ID |
|------|----|
| Workspace | `20557679` |
| Teams custom field | `0329703a-9509-4839-96a6-2c4e23ec2343` |
| SW option (in Teams) | `9a9779da-dadf-49d9-a878-489b00ebbaa5` |

## Source Spaces

| Space | ID |
|-------|----|
| Missions | `32297811` |
| Projects | `90112012593` |
| Gov Contracts | `90110481920` |

## Filtering by Teams Custom Field

**The `--custom-field` CLI filter does not work reliably for
`labels`-type fields.** Instead, fetch all tasks from each space and
filter client-side:

```python
FIELD_ID = "0329703a-9509-4839-96a6-2c4e23ec2343"
SW_OPTION = "9a9779da-dadf-49d9-a878-489b00ebbaa5"

for t in all_tasks:
    for cf in t.get("custom_fields", []):
        if cf.get("id") == FIELD_ID:
            if SW_OPTION in (cf.get("value") or []):
                sw_tasks.append(t)
            break
```

## Workflow

### Step 1 — Fetch all tasks from each space

Paginate through all three spaces:

```bash
clickup task search --space-id <space_id> --order-by due_date --format json --page <n>
```

Increment `--page` until the result set is empty.

### Step 2 — Filter for SW team

Apply client-side filter: keep tasks where the Teams custom field
`value` array contains the SW option ID (`9a9779da...`).

### Step 3 — Classify tasks

- **Timeline**: active (not closed), has a due date, not backlog/idle/blocked
- **Backlog**: active, status is backlog/idle/blocked, or no due date
- **Closed**: skip entirely

### Step 4 — Build the report

#### Header

```markdown
# Software Milestones

_Generated: {today's date}_

Software milestones across Missions, Projects, and Gov Contracts
spaces — tasks tagged with **SW** in the Teams custom field.

**Active milestones:** N | **Backlog:** N | **Total SW tasks (non-closed):** N
```

#### Timeline

Group by month (`### April 2026`, etc.), sorted chronologically.
Each month is a table:

| Date | Source | Mission/Program | Milestone | Status | Ticket |

- **OVERDUE**: mark tasks whose due date has passed
- **SOON**: mark tasks due within 30 days
- Source = which space (Missions, Projects, Gov Contracts)
- Mission/Program = folder name or list name
- Ticket = `[MIS-XXXX](url)`, `[PROJ-XXXX](url)`, or `[GOV-XXXX](url)`

#### Backlog

A single table:

| Source | Mission/Program | Milestone | Status | Ticket |

### Step 5 — Write the report

Write to `reports/software-milestones.md` using the Write tool.

### Step 6 — Report to user

Provide a summary:
- Output file path
- Active milestone count
- Backlog count
- Timeline date range
- Any overdue items
