#!/usr/bin/env bash
#
# Safely fetch and pull all workspace repositories.
# Skips repos that have uncommitted changes, detached HEAD, no remote/upstream,
# unpushed commits, or merge conflicts.
#

set -euo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspaces/trl-work}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

updated=0
skipped=0
failed=0

for dir in "${WORKSPACE_DIR}"/.devcontainer/ "${WORKSPACE_DIR}"/*/; do
    [ -d "${dir}.git" ] || continue
    repo="$(basename "$dir")"

    cd "$dir"
    printf "${BOLD}%-25s${RESET}" "$repo"

    # Check for detached HEAD
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")
    if [ "$branch" = "HEAD" ]; then
        echo -e "${YELLOW}SKIPPED${RESET} — detached HEAD  ${DIM}(detached)${RESET}"
        skipped=$((skipped + 1))
        continue
    fi

    # Check for uncommitted changes
    dirty=$(git status --porcelain 2>/dev/null | wc -l)
    if [ "$dirty" -gt 0 ]; then
        echo -e "${YELLOW}SKIPPED${RESET} — ${dirty} uncommitted change(s)  ${DIM}(${branch})${RESET}"
        skipped=$((skipped + 1))
        continue
    fi

    # Check for merge conflicts
    conflicts=$(git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
    if [ "$conflicts" -gt 0 ]; then
        echo -e "${YELLOW}SKIPPED${RESET} — ${conflicts} merge conflict(s)  ${DIM}(${branch})${RESET}"
        skipped=$((skipped + 1))
        continue
    fi

    # Check for remotes
    remote_count=$(git remote 2>/dev/null | wc -l)
    if [ "$remote_count" -eq 0 ]; then
        echo -e "${YELLOW}SKIPPED${RESET} — no remotes configured  ${DIM}(${branch})${RESET}"
        skipped=$((skipped + 1))
        continue
    fi

    # Fetch all remotes
    if ! git fetch --all --tags --prune >/dev/null 2>&1; then
        echo -e "${RED}FAILED${RESET} — fetch error"
        failed=$((failed + 1))
        continue
    fi

    # Check for upstream tracking
    upstream=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
    if [ -z "$upstream" ]; then
        echo -e "${CYAN}FETCHED${RESET} — no upstream tracking for ${branch}"
        skipped=$((skipped + 1))
        continue
    fi

    # Check for unpushed commits (would be lost in a reset, safe with pull but worth noting)
    ahead=$(git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "0")

    # Check how far behind
    behind=$(git rev-list --count "HEAD..${upstream}" 2>/dev/null || echo "0")
    if [ "$behind" -eq 0 ]; then
        echo -e "${GREEN}UP TO DATE${RESET}  ${DIM}(${branch})${RESET}"

        # Sync submodules if any are out of date
        if [ -f .gitmodules ]; then
            outdated_subs=$(git submodule status --recursive 2>/dev/null | grep -c '^+' || true)
            if [ "$outdated_subs" -gt 0 ]; then
                if git submodule update --init --recursive >/dev/null 2>&1; then
                    printf "${BOLD}%-25s${RESET}" ""
                    echo -e "${DIM}synced ${outdated_subs} submodule(s)${RESET}"
                else
                    printf "${BOLD}%-25s${RESET}" ""
                    echo -e "${YELLOW}submodule update failed${RESET}"
                fi
            fi
        fi
        continue
    fi

    # Pull (fast-forward only to avoid creating merge commits)
    if git merge --ff-only "${upstream}" >/dev/null 2>&1; then
        msg="${GREEN}UPDATED${RESET} — pulled ${behind} commit(s)"
        if [ "$ahead" -gt 0 ]; then
            msg="${msg} ${DIM}(${ahead} unpushed)${RESET}"
        fi
        echo -e "${msg}  ${DIM}(${branch})${RESET}"
        updated=$((updated + 1))

        # Update submodules if the repo has any
        if [ -f .gitmodules ]; then
            if git submodule update --init --recursive >/dev/null 2>&1; then
                printf "${BOLD}%-25s${RESET}" ""
                echo -e "${DIM}submodules synced${RESET}"
            else
                printf "${BOLD}%-25s${RESET}" ""
                echo -e "${YELLOW}submodule update failed${RESET}"
            fi
        fi
    else
        echo -e "${YELLOW}SKIPPED${RESET} — cannot fast-forward ${branch} (${behind} behind, ${ahead} ahead)"
        skipped=$((skipped + 1))
    fi
done

echo ""
echo -e "${GREEN}${updated} updated${RESET}, ${YELLOW}${skipped} skipped${RESET}, ${RED}${failed} failed${RESET}"
