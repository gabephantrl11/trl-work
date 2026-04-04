# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workspace Overview

This is TRL11's multi-repo development workspace (`trl-work`). It contains independent git repositories for space communication, video, and infrastructure systems. Each repo has its own build system, and many have their own `CLAUDE.md` with repo-specific guidance — always read the repo's `CLAUDE.md` before working in it.

## Repository Map

| Repo | Description |
|------|-------------|
| `threat_assessment` | RSO threat assessment (C++17, orbital propagation) |
| `trl-commander` | Command-and-control app (Python/FastAPI backend + React frontend) |
| `trl-eng-servers` | Engineering server infrastructure (Jenkins, Gitea, Docker services) |
| `trl-foveactl` | MQTT control daemon for MevoCam cameras |
| `trl-forge` | Electron desktop app for flashing/configuring TRL11 hardware |
| `trl-jetson-bsp` | Jetson BSP — full Linux distro builds for Jetson SoCs |
| `trl-orbitvision` | MQTT telescope mount control (Celestron NexStar) |
| `trl-saver` | SAVER video recorder for NVIDIA Jetson (Python + React) |
| `trl-saver-2.x` | SAVER 2.x branch (same upstream as trl-saver) |
| `trl-telescopectrl` | MQTT telescope mount control |
| `trl-udl` | UDL (Unified Data Library) helper scripts |
| `trl-vip1st` | VIP1st file format and priority transmission |
| `trl-viplink` | VIPLink satellite communication protocol (C++ core + Python bindings) |
| `trl-viponly` | VIP Only (LUMI) — lightweight VIPLink-only system |
| `trl-xclops-ng` | Next-gen Xclops video system for Jetson Orin NX |

## Devcontainer

```bash
make dev          # Start devcontainer and attach shell (from host)
make dev-stop     # Stop devcontainer
```

Inside the container, the workspace is at `/workspaces/trl-work`.

## Repo Tool

Use the `repo` skill (`/repos`) to manage workspace repositories. It wraps `tools/repo.sh` and operates across all repos by default, or a single repo with `repo-<name>-<cmd>`.

Available commands:

| Command | Description |
|---------|-------------|
| `report` | Summary table of all repos (default) |
| `sync` | Check GitHub via `gh` and pull only repos with new commits |
| `status` | Working tree status across repos |
| `update` | Fetch and fast-forward clean repos |
| `fetch` | Fetch all remotes |
| `health` | Check repo health |
| `log` | Recent commits |
| `changelog` | Oneline log with author, date, subject |
| `branches` | Show branches |
| `unpushed` | Unpushed commits, untracked branches, stashes |
| `outdated` | Repos behind their upstream |
| `exec` | Run an arbitrary command in each repo |

## Skills

Workspace-level skills are in `.claude/skills/`:

- `/repos` — Repository management (see Repo Tool above)
- `/clickup-timesheet` — Generate and submit ClickUp time entries from sprint tickets and git history
- `/missions-summary` — Generate missions & projects summary report to `reports/`
- `/software-milestones` — Generate SW team milestones timeline to `reports/`
- `/daily-journal` — Summarize today's work and append to the ClickUp journal
