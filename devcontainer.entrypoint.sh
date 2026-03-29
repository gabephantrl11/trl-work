#!/bin/bash

# Enable core dumps for debugging
ulimit -c unlimited
sudo sysctl -w kernel.core_pattern="/tmp/core.%e.%p" 2>/dev/null || true

# Setup X11 and XDG runtime directory for GUI applications
if [ -n "$XDG_RUNTIME_DIR" ]; then
    mkdir -p "$XDG_RUNTIME_DIR"
    chmod 700 "$XDG_RUNTIME_DIR"
fi

# Allow X11 connections from the container
if [ -n "$DISPLAY" ]; then
    xhost +local: 2>/dev/null || true
fi

# Source the standard bashrc first (for git-prompt, etc.)
if [ -f ~/.bashrc ]; then
    source ~/.bashrc
fi

# Load HOST_USER and HOST_NAME from .env
if [ -f "${WORKSPACE_DIR}/.devcontainer/.env" ]; then
    export $(grep -E '^(HOST_USER|HOST_NAME)=' "${WORKSPACE_DIR}/.devcontainer/.env" | xargs)
fi

# Show banner
source "${WORKSPACE_DIR}/.devcontainer/banner.sh"

# Determine if this script is being used as a terminal initialization file or run directly
if [[ "$0" != "${BASH_SOURCE[0]}" ]]; then
    echo -e "\e[32mLet's GO!\n\e[0m"
fi
