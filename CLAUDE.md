# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Workspace Overview

This is TRL11's multi-repo development workspace (`trl-work`). It contains independent git repositories for space communication, video, and infrastructure systems. Each repo has its own build system, and many have their own `CLAUDE.md` with repo-specific guidance — always read the repo's `CLAUDE.md` before working in it.

## Repository Map

| Repo | Description |
|------|-------------|
| `trl-viplink` | VIPLink satellite communication protocol (C++ core + Python bindings) |
| `trl-saver` | SAVER video recorder for NVIDIA Jetson (Python + React) |
| `trl-saver-2.x` | SAVER 2.x branch (same upstream as trl-saver) |
| `trl-commander` | Command-and-control app (Python/FastAPI backend + React frontend) |
| `trl-xclops-ng` | Next-gen Xclops video system for Jetson Orin NX |
| `trl-viponly` | VIP Only (LUMI) — lightweight VIPLink-only system |
| `trl-vip1st` | VIP1st file format and priority transmission |
| `threat_assessment` | RSO threat assessment (C++17, orbital propagation) |
| `trl-jetson-bsp` | Jetson BSP — full Linux distro builds for Jetson SoCs |
| `trl-yocto-bsp` | Yocto-based BSP for Jetson (Orin NX / JetPack 6.2.1) |
| `trl-foveactl` | MQTT control daemon for MevoCam cameras |
| `trl-orbitvision` | MQTT telescope mount control (Celestron NexStar) |
| `trl-telescopectrl` | MQTT telescope mount control |
| `trl-forge` | Electron desktop app for flashing/configuring TRL11 hardware |
| `trl-udl` | UDL (Unified Data Library) helper scripts |
| `trl-eng-servers` | Engineering server infrastructure (Jenkins, Gitea, Docker services) |
| `trl-jojo-ai` | AI code search and engineering knowledge base |

## Devcontainer

```bash
make dev          # Start devcontainer and attach shell (from host)
make dev-stop     # Stop devcontainer
```

Inside the container, the workspace is at `/workspaces/trl-work`.

## Common Patterns Across Repos

Most repos follow the same Makefile conventions:

```bash
make help         # List all targets
make build        # Build all components
make check        # Lint and format check
make format       # Auto-fix lint and formatting
make test         # Run all tests
make verify       # Clean + check + build + test
make develop      # Install Python modules in editable mode
make deps         # Install dependencies
make update       # Init/update git submodules
make package      # Build distributable package (.deb or .whl)
```

Component delegation pattern: `make <component>-<target>` (e.g., `make frontend-build`, `make pyviplink-test`).

Cross-compilation for Jetson ARM64: `CROSS_BUILD=1 make build`.

## Tech Stack

- **Python**: 3.10, `uv` for venv/pip, `ruff` for linting/formatting, `pytest` for tests
- **Frontend**: React + TypeScript + Vite, `eslint` + `prettier`, `vitest` for unit tests, Playwright for E2E
- **C/C++**: CMake, `clang-format`, `clang-tidy`, GTest
- **Infrastructure**: Docker Compose, MQTT (Mosquitto), FastAPI, NVIDIA Jetson (ARM64)
- **Packaging**: Debian packages (`dpkg-deb`) and Python wheels; version from `VERSION` file in each repo

## Engineering Server & CI

The `trl-eng-servers` repo manages CI/CD infrastructure. Key tools available in the devcontainer:

- `jkw` — Jenkins CLI wrapper (auto-supplies keyring passphrase)
- `tea` — Gitea CLI for PR/issue management
- `gh` — GitHub CLI

CI workflow: code is reviewed on Gitea, then promoted to GitHub via the automator service. Never push directly to GitHub — use the promotion workflow.

## Submodule Conventions

Many repos share common dependencies as git submodules under `extras/`:
- `trl-packages` — pre-built FFmpeg, GStreamer, SRT, OpenCV
- `trl-viplink` — satellite communication library
- `trl-foveactl` — camera controller
- `trl-vip1st` — priority file transmission
- `trl-ui-kit` — shared React component library

After cloning or switching branches: `make update` to sync submodules.

## Skills

Workspace-level skills are in `.claude/skills/`:

- `/repo` — Workspace repository management via `repo.sh`. Commands: status, update, report, health, log, changelog, branches, unpushed, fetch, outdated, exec. Defaults to `report` when invoked with no arguments.
