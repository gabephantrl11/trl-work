#!/bin/bash
#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#
# Interactive setup wizard for workspace CLI tools.
# Checks and configures: gh, clickup, gws, slack

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF_FILE="$(cd "${SCRIPT_DIR}/.." && pwd)/setup.conf"

# ---------------------------------------------------------------------------
# Config — load local setup.conf if present
# ---------------------------------------------------------------------------
GH_USERNAME=""
GH_SCOPES=""
CLICKUP_WORKSPACE=""
GWS_EMAIL=""
SLACK_WORKSPACE=""

if [ -f "$CONF_FILE" ]; then
    # shellcheck source=/dev/null
    source "$CONF_FILE"
fi

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;94m'
GRAY='\033[0;90m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf "  ${GREEN}✔${NC}  %b\n" "$*"; }
warn()  { printf "  ${YELLOW}⊘${NC}  %b\n" "$*"; }
err()   { printf "  ${RED}✘${NC}  %b\n" "$*"; }
prompt(){ printf "  ${BLUE}?${NC}  %b " "$*"; }
header() {
    printf "\n  ${BOLD}%s${NC}\n" "$1"
    printf "  ${DIM}%s${NC}\n\n" "$(printf '%.0s─' {1..50})"
}

# Track results for summary
declare -a SUMMARY_NAMES=()
declare -a SUMMARY_STATUS=()
summary_add() { SUMMARY_NAMES+=("$1"); SUMMARY_STATUS+=("$2"); }

# Track config changes for final save
declare -A CONF_UPDATES=()

# Prompt user: returns 0 for yes, 1 for no
confirm() {
    local resp
    prompt "$1 [Y/n]"
    read -r resp
    [[ -z "$resp" || "$resp" =~ ^[Yy] ]]
}

# Present a numbered list of choices. Sets CHOSEN to the selected value.
# Usage: choose "prompt" "option1" "option2" ...
# Returns 1 if user cancels (empty input).
CHOSEN=""
choose() {
    local label="$1"; shift
    local options=("$@")
    local count=${#options[@]}

    if [ "$count" -eq 0 ]; then
        return 1
    fi
    if [ "$count" -eq 1 ]; then
        CHOSEN="${options[0]}"
        return 0
    fi

    local i
    for i in "${!options[@]}"; do
        printf "     ${BOLD}%d)${NC} %s\n" "$((i + 1))" "${options[$i]}"
    done
    printf "\n"
    prompt "$label [1-${count}]"
    local resp
    read -r resp
    if [[ -z "$resp" ]] || ! [[ "$resp" =~ ^[0-9]+$ ]] || [ "$resp" -lt 1 ] || [ "$resp" -gt "$count" ]; then
        return 1
    fi
    CHOSEN="${options[$((resp - 1))]}"
    return 0
}

# Stage a config key update (written to disk at the end).
conf_set() {
    local key="$1" value="$2"
    CONF_UPDATES["$key"]="$value"
}

# Write all staged config updates to setup.conf.
conf_flush() {
    if [ ${#CONF_UPDATES[@]} -eq 0 ]; then
        return
    fi

    # Create setup.conf from example if it does not exist
    local example="${SCRIPT_DIR}/../setup.conf.example"
    if [ ! -f "$CONF_FILE" ] && [ -f "$example" ]; then
        cp "$example" "$CONF_FILE"
    elif [ ! -f "$CONF_FILE" ]; then
        printf "# setup.conf — local account configuration for make setup\n" > "$CONF_FILE"
    fi

    local key value
    for key in "${!CONF_UPDATES[@]}"; do
        value="${CONF_UPDATES[$key]}"
        if grep -q "^${key}=" "$CONF_FILE" 2>/dev/null; then
            # Update existing key
            sed -i "s|^${key}=.*|${key}=${value}|" "$CONF_FILE"
        else
            # Append new key
            printf "%s=%s\n" "$key" "$value" >> "$CONF_FILE"
        fi
    done
}

# Read a secret, showing * for each character typed.
# Reads from /dev/tty and prints stars to /dev/tty so it works inside $().
read_secret() {
    local secret="" char
    while IFS= read -rs -n1 char </dev/tty; do
        if [[ -z "$char" ]]; then
            break
        fi
        if [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
            if [[ -n "$secret" ]]; then
                secret="${secret%?}"
                printf '\b \b' >/dev/tty
            fi
        else
            secret+="$char"
            printf '*' >/dev/tty
        fi
    done
    printf '\n' >/dev/tty
    echo "$secret"
}

# ---------------------------------------------------------------------------
# GitHub CLI (gh)
# ---------------------------------------------------------------------------
setup_gh() {
    header "GitHub CLI (gh)"

    if ! command -v gh &>/dev/null; then
        err "gh is not installed"
        printf "     Install: ${GRAY}https://cli.github.com/${NC}\n"
        summary_add "gh" "missing"
        return
    fi

    # Check current status — use gh api to test the active token directly,
    # since gh auth status exits non-zero if *any* account has a bad token.
    local user name
    user=$(gh api user --jq '.login' 2>/dev/null || echo "")
    if [ -n "$user" ]; then
        name=$(gh api user --jq '.name // empty' 2>/dev/null || echo "")

        # Detect all accounts from gh hosts config
        local hosts_file="${HOME}/.config/gh/hosts.yml"
        local -a gh_accounts=()
        if [ -f "$hosts_file" ]; then
            while IFS= read -r acct; do
                [ -n "$acct" ] && gh_accounts+=("$acct")
            done < <(grep -E '^        [a-zA-Z]' "$hosts_file" | sed 's/:.*//' | awk '{$1=$1};1')
        fi

        if [ -n "$GH_USERNAME" ] && [ "$user" != "$GH_USERNAME" ]; then
            warn "Authenticated as ${GREEN}${user}${NC}${name:+ ($name)} ${YELLOW}(expected ${GH_USERNAME})${NC}"
        else
            info "Authenticated as ${GREEN}${user}${NC}${name:+ ($name)}"
        fi

        # Offer to save to config if not already set or mismatched
        if [ -z "$GH_USERNAME" ]; then
            if [ ${#gh_accounts[@]} -gt 1 ]; then
                printf "\n     Multiple GitHub accounts found:\n"
                if choose "Save which account to setup.conf?" "${gh_accounts[@]}"; then
                    conf_set "GH_USERNAME" "$CHOSEN"
                    info "Will save GH_USERNAME=${CHOSEN}"
                fi
            else
                conf_set "GH_USERNAME" "$user"
                info "Will save GH_USERNAME=${user}"
            fi
        elif [ "$GH_USERNAME" != "$user" ] && [ ${#gh_accounts[@]} -gt 1 ]; then
            printf "\n     Multiple GitHub accounts found:\n"
            if choose "Update GH_USERNAME in setup.conf?" "${gh_accounts[@]}"; then
                conf_set "GH_USERNAME" "$CHOSEN"
                info "Will save GH_USERNAME=${CHOSEN}"
            fi
        fi
        printf "\n"

        summary_add "gh" "ok"
        return
    fi

    printf "     Not authenticated.\n\n"

    if ! confirm "Set up GitHub CLI?"; then
        warn "Skipping GitHub CLI"
        summary_add "gh" "skipped"
        return
    fi

    local scopes="${GH_SCOPES:-repo read:org workflow}"
    printf "\n     Create a ${GREEN}classic${NC} personal access token (not fine-grained):\n"
    printf "       1. Go to ${GRAY}https://github.com/settings/tokens${NC}\n"
    printf "       2. Click ${GREEN}Generate new token${NC} > ${GREEN}Generate new token (classic)${NC}\n"
    printf "       3. Set an expiration (e.g. 90 days)\n"
    printf "       4. Select scopes: ${GREEN}%s${NC}\n" "$(echo "$scopes" | sed 's/ /, /g')"
    printf "       5. Click ${GREEN}Generate token${NC} and copy it\n\n"

    while true; do
        prompt "GitHub token:"
        token=$(read_secret)

        if [ -z "$token" ]; then
            warn "No token entered, skipping"
            summary_add "gh" "skipped"
            return
        fi

        local errfile
        errfile=$(mktemp)
        if printf '%s' "$token" | gh auth login --with-token >"$errfile" 2>&1; then
            rm -f "$errfile"
            local user name
            user=$(gh api user --jq '.login' 2>/dev/null || echo "unknown")
            name=$(gh api user --jq '.name // empty' 2>/dev/null || echo "")
            info "Authenticated as ${GREEN}${user}${NC}${name:+ ($name)}"
            [ -z "$GH_USERNAME" ] && conf_set "GH_USERNAME" "$user"
            summary_add "gh" "ok"
            return
        fi

        err "Authentication failed"
        printf "     ${GRAY}%s${NC}\n" "$(cat "$errfile")"
        rm -f "$errfile"
        if ! confirm "Try again?"; then
            warn "Skipping GitHub CLI"
            summary_add "gh" "skipped"
            return
        fi
    done
}

# ---------------------------------------------------------------------------
# ClickUp CLI
# ---------------------------------------------------------------------------
setup_clickup() {
    header "ClickUp CLI"

    if ! command -v clickup &>/dev/null; then
        err "clickup CLI is not installed"
        printf "     Install: ${GRAY}npm install -g @anthropic/clickup-cli${NC}\n"
        summary_add "clickup" "missing"
        return
    fi

    # Check current status
    local status_output
    status_output=$(clickup auth status 2>&1 || true)
    if ! echo "$status_output" | grep -qi "no.*token\|not.*auth\|error"; then
        # Extract user from auth status (e.g. "User: Gabe Phan (gabe@trl11.com)")
        local cu_user
        cu_user=$(echo "$status_output" | grep -i '^User:' | sed 's/^User: *//' || echo "")

        # Detect workspace(s) — parse id|name pairs from JSON
        local -a cu_ws_ids=() cu_ws_names=() cu_ws_labels=()
        while IFS='|' read -r wid wname; do
            [ -n "$wid" ] || continue
            cu_ws_ids+=("$wid")
            cu_ws_names+=("$wname")
            cu_ws_labels+=("${wname} (${wid})")
        done < <(clickup workspace list 2>/dev/null | node -e "
            const d=[];process.stdin.on('data',c=>d.push(c));
            process.stdin.on('end',()=>{try{const j=JSON.parse(d.join(''));
            const a=Array.isArray(j)?j:[j];
            a.forEach(w=>console.log(w.id+'|'+w.name))}catch(e){}})" 2>/dev/null)

        if [ ${#cu_ws_ids[@]} -gt 0 ]; then
            local ws_id="${cu_ws_ids[0]}"
            local ws_name="${cu_ws_names[0]}"
            local display="${cu_user:+${cu_user} — }${ws_name}"
            if [ -n "$CLICKUP_WORKSPACE" ] && [ "$ws_id" != "$CLICKUP_WORKSPACE" ]; then
                warn "Authenticated as ${GREEN}${display}${NC} ${YELLOW}(expected workspace ${CLICKUP_WORKSPACE})${NC}"
            else
                info "Authenticated as ${GREEN}${display}${NC}"
            fi

            # Offer to save to config if not already set
            if [ -z "$CLICKUP_WORKSPACE" ]; then
                if [ ${#cu_ws_ids[@]} -gt 1 ]; then
                    printf "\n     Multiple workspaces found:\n"
                    if choose "Save which workspace to setup.conf?" "${cu_ws_labels[@]}"; then
                        # Extract ID from the chosen label "Name (id)"
                        local chosen_id
                        chosen_id=$(echo "$CHOSEN" | grep -o '([0-9]*)' | tr -d '()')
                        conf_set "CLICKUP_WORKSPACE" "$chosen_id"
                        info "Will save CLICKUP_WORKSPACE=${chosen_id}"
                    fi
                else
                    conf_set "CLICKUP_WORKSPACE" "$ws_id"
                    info "Will save CLICKUP_WORKSPACE=${ws_id}"
                fi
            fi
        else
            if [ -n "$cu_user" ]; then
                info "Authenticated as ${GREEN}${cu_user}${NC}"
            else
                info "ClickUp CLI is authenticated"
            fi
        fi
        summary_add "clickup" "ok"
        return
    fi

    printf "     Not authenticated.\n\n"

    if ! confirm "Set up ClickUp CLI?"; then
        warn "Skipping ClickUp CLI"
        summary_add "clickup" "skipped"
        return
    fi

    printf "\n     Paste your ClickUp personal API token.\n"
    printf "     Get one at: ${GRAY}ClickUp > Settings > Apps > API Token${NC}\n\n"

    local config_dir="${HOME}/.config/clickup-cli-nodejs"
    local config_file="${config_dir}/config.json"

    while true; do
        prompt "ClickUp API token:"
        token=$(read_secret)

        if [ -z "$token" ]; then
            warn "No token entered, skipping"
            summary_add "clickup" "skipped"
            return
        fi

        # Write token to config (clickup auth login --token has a CLI bug)
        mkdir -p "$config_dir"
        if [ -f "$config_file" ]; then
            local tmp
            tmp=$(mktemp)
            node -e "
                const c = JSON.parse(require('fs').readFileSync('$config_file','utf8'));
                c.profiles = c.profiles || {};
                c.profiles.default = c.profiles.default || {};
                c.profiles.default.token = '$token';
                console.log(JSON.stringify(c, null, '\t'));
            " > "$tmp" && mv "$tmp" "$config_file"
        else
            printf '{\n\t"profiles": { "default": { "token": "%s" } }\n}\n' "$token" > "$config_file"
        fi

        # Validate the token
        local status_output
        status_output=$(clickup auth status 2>&1 || true)
        if ! echo "$status_output" | grep -qi "not authenticated\|no.*token\|error"; then
            local ws_name ws_id
            read -r ws_id ws_name < <(clickup workspace list 2>/dev/null | node -e "
                const d=[];process.stdin.on('data',c=>d.push(c));
                process.stdin.on('end',()=>{try{const j=JSON.parse(d.join(''));
                const w=Array.isArray(j)?j[0]:j;
                console.log(w.id+' '+w.name)}catch(e){}})" 2>/dev/null || echo "")
            if [ -n "$ws_name" ]; then
                info "Connected to workspace: ${GREEN}${ws_name}${NC}"
                [ -z "$CLICKUP_WORKSPACE" ] && conf_set "CLICKUP_WORKSPACE" "$ws_id"
            else
                info "ClickUp CLI authenticated"
            fi
            summary_add "clickup" "ok"
            return
        fi

        err "Token validation failed"
        printf "     ${GRAY}%s${NC}\n" "$status_output"
        if ! confirm "Try again?"; then
            warn "Skipping ClickUp CLI"
            summary_add "clickup" "skipped"
            return
        fi
    done
}

# ---------------------------------------------------------------------------
# Google Workspace CLI (gws)
# ---------------------------------------------------------------------------
setup_gws() {
    header "Google Workspace CLI (gws)"

    if ! command -v gws &>/dev/null; then
        err "gws is not installed"
        printf "     Install: ${GRAY}npm install -g google-workspace-cli${NC}\n"
        summary_add "gws" "missing"
        return
    fi

    # Check current status
    local status_output
    status_output=$(gws auth status 2>&1 || true)
    if echo "$status_output" | grep -q '"token_valid": true'; then
        # Extract email from auth status JSON ("user" field)
        local email
        email=$(echo "$status_output" | grep -o '"user": *"[^"]*"' | head -1 | cut -d'"' -f4 || echo "")
        if [ -n "$email" ]; then
            if [ -n "$GWS_EMAIL" ] && [ "$email" != "$GWS_EMAIL" ]; then
                warn "Authenticated as ${GREEN}${email}${NC} ${YELLOW}(expected ${GWS_EMAIL})${NC}"
            else
                info "Authenticated as ${GREEN}${email}${NC}"
            fi
            if [ -z "$GWS_EMAIL" ]; then
                conf_set "GWS_EMAIL" "$email"
                info "Will save GWS_EMAIL=${email}"
            fi
        else
            info "Google Workspace CLI is authenticated"
        fi
        summary_add "gws" "ok"
        return
    fi

    printf "     Not authenticated.\n\n"

    if ! confirm "Set up Google Workspace CLI?"; then
        warn "Skipping Google Workspace CLI"
        summary_add "gws" "skipped"
        return
    fi

    printf "\n     This opens a browser for Google OAuth2 sign-in.\n"
    printf "     (Requires a GCP project with OAuth credentials.\n"
    printf "      Run ${GRAY}gws auth setup${NC} first if you haven't configured one.)\n\n"

    gws auth login || true

    # Verify
    local email
    email=$(gws gmail users getProfile --params '{"userId":"me"}' 2>/dev/null \
        | grep -o '"emailAddress":"[^"]*"' | cut -d'"' -f4 || echo "")
    if [ -n "$email" ]; then
        info "Authenticated as ${GREEN}${email}${NC}"
        [ -z "$GWS_EMAIL" ] && conf_set "GWS_EMAIL" "$email"
        summary_add "gws" "ok"
    else
        local check
        check=$(gws auth status 2>&1 || true)
        if echo "$check" | grep -qi "error\|no.*credential"; then
            err "Authentication did not complete"
            summary_add "gws" "fail"
        else
            info "Google Workspace CLI configured"
            summary_add "gws" "ok"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Slack CLI
# ---------------------------------------------------------------------------
setup_slack() {
    header "Slack CLI"

    if ! command -v slack &>/dev/null; then
        err "slack CLI is not installed"
        printf "     Install: ${GRAY}https://docs.slack.dev/tools/slack-cli${NC}\n"
        summary_add "slack" "missing"
        return
    fi

    # Check current status
    local auth_output
    auth_output=$(slack auth list 2>&1 || true)
    if ! echo "$auth_output" | grep -qi "not logged in\|no authorized"; then
        # Extract workspace name and user ID from auth list output
        # Format: "\nworkspace_name (Team ID: T...)\nUser ID: U..."
        local slack_workspace slack_user_id
        slack_workspace=$(echo "$auth_output" | grep 'Team ID' | head -1 | sed 's/ *(Team ID:.*//' || echo "")
        slack_user_id=$(echo "$auth_output" | grep -o 'User ID: [^ ]*' | head -1 | sed 's/User ID: //' || echo "")
        if [ -n "$slack_workspace" ]; then
            local display="${slack_workspace}${slack_user_id:+ (${slack_user_id})}"
            if [ -n "$SLACK_WORKSPACE" ] && [ "$slack_workspace" != "$SLACK_WORKSPACE" ]; then
                warn "Authenticated to ${GREEN}${display}${NC} ${YELLOW}(expected ${SLACK_WORKSPACE})${NC}"
            else
                info "Authenticated to ${GREEN}${display}${NC}"
            fi
            if [ -z "$SLACK_WORKSPACE" ]; then
                conf_set "SLACK_WORKSPACE" "$slack_workspace"
                info "Will save SLACK_WORKSPACE=${slack_workspace}"
            fi
        else
            info "Slack CLI is authenticated"
        fi
        summary_add "slack" "ok"
        return
    fi

    printf "     Not authenticated.\n\n"

    if ! confirm "Set up Slack CLI?"; then
        warn "Skipping Slack CLI"
        summary_add "slack" "skipped"
        return
    fi

    printf "\n     Starting Slack interactive login...\n\n"

    slack login || true

    # Verify
    local check
    check=$(slack auth list 2>&1 || true)
    if echo "$check" | grep -qi "not logged in\|no authorized"; then
        err "Authentication did not complete"
        summary_add "slack" "fail"
    else
        local slack_workspace
        slack_workspace=$(echo "$check" | grep 'Team ID' | head -1 | sed 's/ *(Team ID:.*//' || echo "")
        if [ -n "$slack_workspace" ]; then
            info "Authenticated to ${GREEN}${slack_workspace}${NC}"
            [ -z "$SLACK_WORKSPACE" ] && conf_set "SLACK_WORKSPACE" "$slack_workspace"
        else
            info "Slack CLI authenticated"
        fi
        summary_add "slack" "ok"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
print_summary() {
    printf "\n  ${BOLD}Summary${NC}\n"
    printf "  ${DIM}%s${NC}\n" "$(printf '%.0s─' {1..50})"

    local i name status icon color label
    for i in "${!SUMMARY_NAMES[@]}"; do
        name="${SUMMARY_NAMES[$i]}"
        status="${SUMMARY_STATUS[$i]}"
        case "$status" in
            ok)      icon="✔"; color="$GREEN"; label="ready"   ;;
            skipped) icon="⊘"; color="$YELLOW"; label="skipped" ;;
            missing) icon="✘"; color="$RED";    label="not installed" ;;
            fail)    icon="✘"; color="$RED";    label="failed"  ;;
            *)       icon="?"; color="$GRAY";   label="$status" ;;
        esac
        printf "  ${color}${icon}${NC}  %-12s ${DIM}%s${NC}\n" "$name" "$label"
    done
    printf "\n"
}

main() {
    printf "\n"
    printf "  ${BOLD}TRL11 Workspace Setup${NC}\n"
    printf "  ${DIM}Checking CLI tools: gh, clickup, gws, slack${NC}\n"
    if [ -f "$CONF_FILE" ]; then
        printf "  ${DIM}Config: %s${NC}\n" "$CONF_FILE"
    else
        printf "  ${DIM}No setup.conf found — copy setup.conf.example to setup.conf${NC}\n"
    fi

    setup_gh
    setup_clickup
    setup_gws
    setup_slack

    # Save any detected config values
    if [ ${#CONF_UPDATES[@]} -gt 0 ]; then
        header "Saving setup.conf"
        local key
        for key in "${!CONF_UPDATES[@]}"; do
            printf "     ${GREEN}%s${NC}=%s\n" "$key" "${CONF_UPDATES[$key]}"
        done
        printf "\n"
        if confirm "Write these to setup.conf?"; then
            conf_flush
            info "Saved to ${GRAY}${CONF_FILE}${NC}"
        else
            warn "Config not saved"
        fi
    fi

    print_summary
    printf "  ${DIM}Run ${NC}make setup${DIM} again at any time to reconfigure.${NC}\n\n"
}

main "$@"
