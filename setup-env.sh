#!/bin/bash
#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#
# Setup script for devcontainer initialization
# Creates .env file with dynamic values for devcontainer build

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Create directories that will be mounted
mkdir -p "$HOME/.claude"

# Get the required values
DEV_UID=$(id -u)
DEV_GID=$(id -g)
DOCKER_GID=$(getent group docker | cut -d: -f3 2>/dev/null || echo "999")
HOST_USER=$(whoami)
HOST_NAME=$(hostname)

# APT proxy defaults
APT_PROXY_URL="${APT_PROXY_URL:-http://192.168.11.112:3142}"

# Verify proxy is reachable, clear if not
if [ -n "$APT_PROXY_URL" ]; then
    PROXY_HOST=$(echo "$APT_PROXY_URL" | sed 's|https\?://||;s|:.*||')
    PROXY_PORT=$(echo "$APT_PROXY_URL" | sed 's|.*:\([0-9]*\).*|\1|')
    if ! timeout 2 bash -c "echo > /dev/tcp/$PROXY_HOST/$PROXY_PORT" 2>/dev/null; then
        echo "Warning: APT proxy $APT_PROXY_URL is unreachable, bypassing"
        APT_PROXY_URL=""
    fi
fi

# Create .env file
cat > "$ENV_FILE" << EOF
APT_PROXY_URL=$APT_PROXY_URL
DEV_UID=$DEV_UID
DEV_GID=$DEV_GID
DOCKER_GID=$DOCKER_GID
HOST_USER=$HOST_USER
HOST_NAME=$HOST_NAME
EOF
