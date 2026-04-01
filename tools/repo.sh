#!/usr/bin/env bash
#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#
# Unified repository management tool for the workspace.
# Usage: repo.sh <command> [options]

set -euo pipefail

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspaces/trl-work}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

header() {
    echo -e "\n${BOLD}${CYAN}$1${RESET}"
    echo -e "${DIM}$(printf '%.0s─' $(seq 1 ${#1}))${RESET}"
}

repo_label() {
    printf "${BOLD}%-25s${RESET}" "$1"
}

ok()   { echo -e "${GREEN}✓${RESET} $*"; }
warn() { echo -e "${YELLOW}⚠${RESET} $*"; }

REPO_FILTER=""

KNOWN_COMMANDS="list status unpushed branches fetch log changelog outdated health exec report help"

discover_repos() {
    if [ -n "$REPO_FILTER" ]; then
        echo "$REPO_FILTER"
        return
    fi
    for dir in "${WORKSPACE_DIR}"/.devcontainer/ "${WORKSPACE_DIR}"/*/; do
        [ -d "${dir}.git" ] || continue
        local name
        name="$(basename "$dir")"

        echo "$name"
    done | sort
}

in_repo() {
    local repo="$1"; shift
    (cd "${WORKSPACE_DIR}/${repo}" && "$@")
}

# ─── Commands ─────────────────────────────────────────────────────────

cmd_list() {
    local verbose=true
    [[ "${1:-}" == "-q" || "${1:-}" == "--quiet" || "${VERBOSE:-}" == "0" ]] && verbose=false

    local repos
    repos=$(discover_repos)
    local count
    count=$(echo "$repos" | wc -l)

    header "Workspace Repositories (${count})"

    for repo in $repos; do
        if $verbose; then
            local branch remote
            branch=$(in_repo "$repo" git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
            remote=$(in_repo "$repo" git remote get-url origin 2>/dev/null || echo "no remote")
            repo_label "$repo"
            echo -e "${DIM}branch:${RESET} ${branch}  ${DIM}remote:${RESET} ${remote}"
        else
            echo "$repo"
        fi
    done
}

cmd_status() {
    header "Repository Status"

    local clean_count=0
    local dirty_count=0

    for repo in $(discover_repos); do
        local branch status_output staged unstaged untracked
        branch=$(in_repo "$repo" git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
        status_output=$(in_repo "$repo" git status --porcelain 2>/dev/null)

        staged=$(echo "$status_output" | grep -c '^[MADRC]' || true)
        unstaged=$(echo "$status_output" | grep -c '^.[MADRC]' || true)
        untracked=$(echo "$status_output" | grep -c '^??' || true)

        repo_label "$repo"

        if [ -z "$status_output" ]; then
            echo -e "${GREEN}clean${RESET}  ${DIM}(${branch})${RESET}"
            clean_count=$((clean_count + 1))
        else
            local parts=()
            [ "$staged" -gt 0 ] && parts+=("${GREEN}${staged} staged${RESET}")
            [ "$unstaged" -gt 0 ] && parts+=("${YELLOW}${unstaged} modified${RESET}")
            [ "$untracked" -gt 0 ] && parts+=("${RED}${untracked} untracked${RESET}")
            echo -e "$(IFS=', '; echo "${parts[*]}")  ${DIM}(${branch})${RESET}"
            dirty_count=$((dirty_count + 1))
        fi
    done

    echo ""
    echo -e "${GREEN}${clean_count} clean${RESET}, ${YELLOW}${dirty_count} dirty${RESET}"
}

cmd_unpushed() {
    header "Unpushed Changes"

    local found_issues=false

    for repo in $(discover_repos); do
        local issues=()
        local branch upstream

        branch=$(in_repo "$repo" git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        if [ -n "$branch" ]; then
            upstream=$(in_repo "$repo" git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
            if [ -n "$upstream" ]; then
                local ahead
                ahead=$(in_repo "$repo" git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "0")
                [ "$ahead" -gt 0 ] && issues+=("${YELLOW}${ahead} unpushed commit(s) on ${branch}${RESET}")
            else
                issues+=("${RED}${branch} has no upstream tracking branch${RESET}")
            fi
        fi

        while IFS= read -r local_branch; do
            [ -z "$local_branch" ] && continue
            [ "$local_branch" = "$branch" ] && continue
            local has_upstream
            has_upstream=$(in_repo "$repo" git rev-parse --abbrev-ref "${local_branch}@{upstream}" 2>/dev/null || echo "")
            if [ -z "$has_upstream" ]; then
                local local_commits
                local_commits=$(in_repo "$repo" git rev-list --count HEAD.."$local_branch" 2>/dev/null || echo "0")
                issues+=("${DIM}branch ${RESET}${local_branch}${DIM} has no upstream (${local_commits} commit(s) ahead)${RESET}")
            else
                local local_ahead
                local_ahead=$(in_repo "$repo" git rev-list --count "${has_upstream}..${local_branch}" 2>/dev/null || echo "0")
                [ "$local_ahead" -gt 0 ] && issues+=("${YELLOW}branch ${local_branch}: ${local_ahead} unpushed commit(s)${RESET}")
            fi
        done < <(in_repo "$repo" git for-each-ref --format='%(refname:short)' refs/heads/ 2>/dev/null)

        local stash_count
        stash_count=$(in_repo "$repo" git stash list 2>/dev/null | wc -l)
        [ "$stash_count" -gt 0 ] && issues+=("${CYAN}${stash_count} stash(es)${RESET}")

        if [ ${#issues[@]} -gt 0 ]; then
            found_issues=true
            repo_label "$repo"
            echo ""
            for issue in "${issues[@]}"; do
                echo -e "  $issue"
            done
        fi
    done

    if ! $found_issues; then
        ok "All repositories are fully pushed"
    fi
}

cmd_branches() {
    local show_all=false
    [[ "${1:-}" == "-a" || "${1:-}" == "--all" || "${ALL:-}" == "1" ]] && show_all=true

    header "Repository Branches"

    for repo in $(discover_repos); do
        local current branches branch_count
        current=$(in_repo "$repo" git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")

        if $show_all; then
            branches=$(in_repo "$repo" git branch -a --format='%(refname:short)' 2>/dev/null)
        else
            branches=$(in_repo "$repo" git branch --format='%(refname:short)' 2>/dev/null)
        fi

        branch_count=$(echo "$branches" | wc -l)
        repo_label "$repo"
        echo -e "${DIM}(${branch_count} branches, current: ${RESET}${GREEN}${current}${RESET}${DIM})${RESET}"

        while IFS= read -r b; do
            [ -z "$b" ] && continue
            if [ "$b" = "$current" ]; then
                echo -e "  ${GREEN}* ${b}${RESET}"
            else
                echo -e "  ${DIM}  ${b}${RESET}"
            fi
        done <<< "$branches"
    done
}

cmd_fetch() {
    local prune_flag=""
    [[ "${1:-}" == "-p" || "${1:-}" == "--prune" || "${PRUNE:-}" == "1" ]] && prune_flag="--prune"

    header "Fetching All Repositories"

    local success=0
    local failed=0

    for repo in $(discover_repos); do
        repo_label "$repo"
        if in_repo "$repo" git fetch --all --tags $prune_flag >/dev/null 2>&1; then
            echo -e "${GREEN}ok${RESET}"
            success=$((success + 1))
        else
            echo -e "${RED}failed${RESET}"
            failed=$((failed + 1))
        fi
    done

    echo ""
    echo -e "${GREEN}${success} succeeded${RESET}, ${RED}${failed} failed${RESET}"
}

cmd_log() {
    local count="${1:-${COUNT:-3}}"

    header "Recent Commits (last ${count} per repo)"

    for repo in $(discover_repos); do
        repo_label "$repo"
        echo ""
        in_repo "$repo" git log \
            --oneline \
            --decorate \
            --color=always \
            -n "$count" \
            --format="  %C(yellow)%h%C(reset) %C(dim)%cr%C(reset) %s %C(blue)(%an)%C(reset)" \
            2>/dev/null || echo -e "  ${DIM}(no commits)${RESET}"
    done
}

cmd_changelog() {
    local since="${1:-${SINCE:-}}"
    local until="${2:-${UNTIL:-}}"

    if [ -z "$since" ] || [ -z "$until" ]; then
        echo -e "${RED}Usage: repo.sh changelog <since> <until>${RESET}"
        echo -e "  Dates in YYYY-MM-DD format."
        echo -e "  Example: repo.sh changelog 2026-03-01 2026-03-31"
        echo -e "  Or via env: make repos-changelog SINCE=2026-03-01 UNTIL=2026-03-31"
        exit 1
    fi

    header "Changelog (${since} .. ${until})"

    for repo in $(discover_repos); do
        local output
        output=$(in_repo "$repo" git log \
            --oneline \
            --since="$since" \
            --until="$until" \
            --format="%ai  %an  %s%d" \
            --date=iso \
            2>/dev/null || true)

        if [ -n "$output" ]; then
            repo_label "$repo"
            echo ""
            echo "$output" | sed 's/^/  /'
        fi
    done
}

cmd_outdated() {
    header "Outdated Repositories (behind upstream)"

    local found=false

    for repo in $(discover_repos); do
        local branch upstream behind
        branch=$(in_repo "$repo" git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
        [ -z "$branch" ] && continue

        upstream=$(in_repo "$repo" git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
        [ -z "$upstream" ] && continue

        behind=$(in_repo "$repo" git rev-list --count "HEAD..${upstream}" 2>/dev/null || echo "0")
        if [ "$behind" -gt 0 ]; then
            found=true
            repo_label "$repo"
            echo -e "${CYAN}${behind} commit(s) behind${RESET} ${upstream}  ${DIM}(${branch})${RESET}"
        fi
    done

    if ! $found; then
        ok "All repositories are up to date with their upstreams"
    fi
}

cmd_health() {
    header "Repository Health Check"

    local total_warnings=0

    for repo in $(discover_repos); do
        local warnings=()
        local branch

        branch=$(in_repo "$repo" git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")

        [ "$branch" = "HEAD" ] && warnings+=("${RED}detached HEAD${RESET}")

        local dirty
        dirty=$(in_repo "$repo" git status --porcelain 2>/dev/null | wc -l)
        [ "$dirty" -gt 0 ] && warnings+=("${YELLOW}${dirty} uncommitted change(s)${RESET}")

        if [ "$branch" != "HEAD" ] && [ "$branch" != "UNKNOWN" ]; then
            local upstream
            upstream=$(in_repo "$repo" git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
            if [ -n "$upstream" ]; then
                local ahead behind
                ahead=$(in_repo "$repo" git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "0")
                behind=$(in_repo "$repo" git rev-list --count "HEAD..${upstream}" 2>/dev/null || echo "0")
                [ "$ahead" -gt 0 ] && warnings+=("${YELLOW}${ahead} ahead${RESET}")
                [ "$behind" -gt 0 ] && warnings+=("${CYAN}${behind} behind${RESET}")
            else
                warnings+=("${DIM}no upstream tracking${RESET}")
            fi
        fi

        local stash_count
        stash_count=$(in_repo "$repo" git stash list 2>/dev/null | wc -l)
        [ "$stash_count" -gt 0 ] && warnings+=("${CYAN}${stash_count} stash(es)${RESET}")

        local remote_count
        remote_count=$(in_repo "$repo" git remote 2>/dev/null | wc -l)
        [ "$remote_count" -eq 0 ] && warnings+=("${RED}no remotes${RESET}")

        if [ -f "${WORKSPACE_DIR}/${repo}/.gitmodules" ]; then
            local sub_issues
            sub_issues=$(in_repo "$repo" git submodule status 2>/dev/null | grep -c '^[-+]' || true)
            [ "$sub_issues" -gt 0 ] && warnings+=("${YELLOW}${sub_issues} submodule(s) out of sync${RESET}")
        fi

        local conflict_count
        conflict_count=$(in_repo "$repo" git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
        [ "$conflict_count" -gt 0 ] && warnings+=("${RED}${conflict_count} merge conflict(s)${RESET}")

        repo_label "$repo"
        if [ ${#warnings[@]} -eq 0 ]; then
            echo -e "${GREEN}healthy${RESET}  ${DIM}(${branch})${RESET}"
        else
            total_warnings=$((total_warnings + ${#warnings[@]}))
            echo -e "$(IFS=', '; echo "${warnings[*]}")  ${DIM}(${branch})${RESET}"
        fi
    done

    echo ""
    if [ "$total_warnings" -eq 0 ]; then
        ok "All repositories are healthy"
    else
        warn "${total_warnings} warning(s) found"
    fi
}

cmd_exec() {
    if [ $# -eq 0 ] && [ -z "${CMD:-}" ]; then
        echo "Usage: repo.sh exec <git-command> [args...]"
        echo "Example: repo.sh exec log --oneline -1"
        exit 1
    fi

    if [ $# -eq 0 ] && [ -n "${CMD:-}" ]; then
        set -- $CMD
    fi

    header "Executing: git $*"

    for repo in $(discover_repos); do
        repo_label "$repo"
        echo ""
        in_repo "$repo" git "$@" 2>&1 | sed 's/^/  /'
    done
}

cmd_help() {
    echo ""
    echo -e "${BOLD}repo.sh — workspace repository management${RESET}"
    echo ""
    echo -e "${BOLD}Usage:${RESET}"
    echo -e "  make repos-<command>             Run on all repos"
    echo -e "  make repo-<name>-<command>       Run on a single repo"
    echo ""
    echo -e "${BOLD}Commands:${RESET}"
    echo -e "  ${CYAN}list${RESET}            List repositories"
    echo -e "  ${CYAN}status${RESET}          Show git status summary"
    echo -e "  ${CYAN}unpushed${RESET}        Check for unpushed commits, untracked branches, stashes"
    echo -e "  ${CYAN}branches${RESET}        Show branches"
    echo -e "  ${CYAN}fetch${RESET}           Fetch all remotes"
    echo -e "  ${CYAN}log${RESET}             Show recent commits (default: 3)"
    echo -e "  ${CYAN}changelog${RESET}       Oneline log with author, date, subject, refs by date range"
    echo -e "  ${CYAN}outdated${RESET}        Show repos behind their upstream"
    echo -e "  ${CYAN}health${RESET}          Comprehensive health check"
    echo -e "  ${CYAN}exec${RESET}            Execute a git command"
    echo -e "  ${CYAN}report${RESET}          Show repos needing attention"
    echo -e "  ${CYAN}help${RESET}            Show this help message"
    echo ""
    echo -e "${BOLD}Examples:${RESET}"
    echo -e "  make repos-report              Report for all repos"
    echo -e "  make repo-trl-viponly-status   Status for trl-viponly only"
    echo -e "  make repo-trl-saver-log        Recent commits for trl-saver"
    echo ""
    echo -e "${BOLD}Options (environment variables):${RESET}"
    echo -e "  ${CYAN}VERBOSE=0${RESET}            Quiet output (e.g., make repo-list VERBOSE=0)"
    echo -e "  ${CYAN}ALL=1${RESET}                Include remotes (e.g., make repo-branches ALL=1)"
    echo -e "  ${CYAN}PRUNE=1${RESET}              Prune stale tracking branches (e.g., make repo-fetch PRUNE=1)"
    echo -e "  ${CYAN}COUNT=N${RESET}              Number of commits to show (e.g., make repo-log COUNT=5)"
    echo -e "  ${CYAN}CMD=\"...\"${RESET}            Git command to execute (e.g., make repo-exec CMD=\"remote -v\")"
    echo -e "  ${CYAN}SINCE=YYYY-MM-DD${RESET}   Start date for changelog (e.g., make repos-changelog SINCE=2026-03-01 UNTIL=2026-03-31)"
    echo -e "  ${CYAN}UNTIL=YYYY-MM-DD${RESET}   End date for changelog"
    echo ""
}

cmd_report() {
    local -a rows=()
    local max_repo=4 max_branch=6 max_reason=6 max_resolve=14

    for repo in $(discover_repos); do
        local branch row_branch reason resolve
        local -a reasons=()
        local -a resolves=()
        branch=$(in_repo "$repo" git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "UNKNOWN")

        if [ "$branch" = "HEAD" ]; then
            row_branch="detached"
            reasons+=("Detached HEAD")
            resolves+=("git checkout <branch>")
        elif [ "$branch" = "UNKNOWN" ]; then
            row_branch="unknown"
            reasons+=("Cannot read branch")
            resolves+=("Check repository state")
        else
            row_branch="$branch"

            local dirty
            dirty=$(in_repo "$repo" git status --porcelain 2>/dev/null | wc -l)
            if [ "$dirty" -gt 0 ]; then
                if [ "$dirty" -eq 1 ]; then
                    reasons+=("1 uncommitted change")
                else
                    reasons+=("${dirty} uncommitted changes")
                fi
                resolves+=("git stash or commit changes")
            fi

            local conflicts
            conflicts=$(in_repo "$repo" git diff --name-only --diff-filter=U 2>/dev/null | wc -l)
            if [ "$conflicts" -gt 0 ]; then
                reasons+=("${conflicts} merge conflict(s)")
                resolves+=("Resolve conflicts and git add")
            fi

            local remote_count
            remote_count=$(in_repo "$repo" git remote 2>/dev/null | wc -l)
            if [ "$remote_count" -eq 0 ]; then
                reasons+=("No remotes")
                resolves+=("git remote add origin <url>")
            else
                local upstream
                upstream=$(in_repo "$repo" git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
                if [ -z "$upstream" ]; then
                    reasons+=("No upstream tracking")
                    resolves+=("git push -u origin ${branch}")
                else
                    local ahead behind
                    ahead=$(in_repo "$repo" git rev-list --count "${upstream}..HEAD" 2>/dev/null || echo "0")
                    behind=$(in_repo "$repo" git rev-list --count "HEAD..${upstream}" 2>/dev/null || echo "0")
                    if [ "$behind" -gt 0 ]; then
                        reasons+=("${behind} behind")
                        resolves+=("git pull")
                    fi
                    if [ "$ahead" -gt 0 ]; then
                        reasons+=("${ahead} ahead")
                        resolves+=("git push")
                    fi
                fi
            fi
        fi

        if [ ${#reasons[@]} -eq 0 ]; then
            reason="OK"
            resolve=""
        else
            reason=$(printf '%s' "${reasons[0]}"; for r in "${reasons[@]:1}"; do printf ', %s' "$r"; done)
            resolve=$(printf '%s' "${resolves[0]}"; for r in "${resolves[@]:1}"; do printf ', %s' "$r"; done)
        fi

        rows+=("${repo}|${row_branch}|${reason}|${resolve}")

        [ ${#repo} -gt $max_repo ] && max_repo=${#repo}
        [ ${#row_branch} -gt $max_branch ] && max_branch=${#row_branch}
        [ ${#reason} -gt $max_reason ] && max_reason=${#reason}
        [ ${#resolve} -gt $max_resolve ] && max_resolve=${#resolve}
    done

    local w_repo=$((max_repo + 2))
    local w_branch=$((max_branch + 2))
    local w_reason=$((max_reason + 2))
    local w_resolve=$((max_resolve + 2))

    draw_line() {
        local left="$1" mid="$2" right="$3"
        printf "%s" "$left"
        printf "%0.s─" $(seq 1 $w_repo); printf "%s" "$mid"
        printf "%0.s─" $(seq 1 $w_branch); printf "%s" "$mid"
        printf "%0.s─" $(seq 1 $w_reason); printf "%s" "$mid"
        printf "%0.s─" $(seq 1 $w_resolve); printf "%s\n" "$right"
    }

    print_cell() {
        local width="$1" color="$2" text="$3"
        local pad=$((width - 1 - ${#text}))
        printf "│ %b%-s%b%*s" "$color" "$text" "$RESET" "$pad" ""
    }

    print_row() {
        local c1="$1" c2="$2" c3="$3" c4="$4"
        local color1="${5:-}" color2="${6:-}" color3="${7:-}" color4="${8:-}"
        print_cell "$w_repo" "$color1" "$c1"
        print_cell "$w_branch" "$color2" "$c2"
        print_cell "$w_reason" "$color3" "$c3"
        print_cell "$w_resolve" "$color4" "$c4"
        printf "│\n"
    }

    local issues=0
    for row in "${rows[@]}"; do
        IFS='|' read -r _ _ r_reason _ <<< "$row"
        [ "$r_reason" != "OK" ] && issues=$((issues + 1))
    done

    header "Workspace Report"

    if [ "$issues" -eq 0 ]; then
        echo -e "${GREEN}All ${#rows[@]} repositories are healthy${RESET}"
    else
        echo -e "${YELLOW}${issues} of ${#rows[@]} repo(s) need attention${RESET}"
    fi
    echo ""

    draw_line "┌" "┬" "┐"
    print_row "Repo" "Branch" "Reason" "How to Resolve" "$BOLD" "$BOLD" "$BOLD" "$BOLD"
    draw_line "├" "┼" "┤"

    local i=0
    for row in "${rows[@]}"; do
        IFS='|' read -r r_repo r_branch r_reason r_resolve <<< "$row"
        local rc
        if [ "$r_reason" = "OK" ]; then
            rc="$GREEN"
        else
            rc="$YELLOW"
        fi
        local bc="$DIM"
        if [[ "$r_branch" != "dev" && "$r_branch" != "main" && "$r_branch" != "master" ]]; then
            bc="$CYAN"
        fi
        print_row "$r_repo" "$r_branch" "$r_reason" "$r_resolve" "$BOLD" "$bc" "$rc" "$DIM"
        i=$((i + 1))
        if [ $i -lt ${#rows[@]} ]; then
            draw_line "├" "┼" "┤"
        fi
    done

    draw_line "└" "┴" "┘"
}

# ─── Single-repo mode ─────────────────────────────────────────────────

parse_single() {
    local input="$1"
    local cmd repo_name

    for cmd in $KNOWN_COMMANDS; do
        if [[ "$input" == *"-${cmd}" ]]; then
            repo_name="${input%-"${cmd}"}"
            if [ -d "${WORKSPACE_DIR}/${repo_name}/.git" ]; then
                REPO_FILTER="$repo_name"
                PARSED_COMMAND="$cmd"
                return
            fi
        fi
    done

    echo -e "${RED}Cannot parse '${input}' into <repo>-<command>${RESET}" >&2
    echo -e "Expected: ${CYAN}repo-<name>-<command>${RESET} (e.g., repo-trl-viponly-report)" >&2
    exit 1
}

# ─── Main ─────────────────────────────────────────────────────────────

if [ "${1:-}" = "--single" ]; then
    shift
    parse_single "$1"
    command="$PARSED_COMMAND"
    shift
else
    command="${1:-help}"
    shift || true
fi

case "$command" in
    list)       cmd_list "$@" ;;
    status)     cmd_status "$@" ;;
    unpushed)   cmd_unpushed "$@" ;;
    branches)   cmd_branches "$@" ;;
    fetch)      cmd_fetch "$@" ;;
    log)        cmd_log "$@" ;;
    changelog)  cmd_changelog "$@" ;;
    outdated)   cmd_outdated "$@" ;;
    health)     cmd_health "$@" ;;
    exec)       cmd_exec "$@" ;;
    report)     cmd_report "$@" ;;
    help|--help|-h) cmd_help ;;
    *)
        echo -e "${RED}Unknown command: ${command}${RESET}" >&2
        cmd_help
        exit 1
        ;;
esac
