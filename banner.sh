#!/bin/bash

USERNAME=${HOST_USER:-${USER:-$(whoami)}}
CURRENT_DIR=${WORKSPACE_VOLUME:-$(pwd)}
BUILD_DATE=${DEVCONTAINER_BUILD_DATE:-"unknown"}

GRN="\e[32m"
YEL="\e[33m"
BLU="\e[34m"
CYN="\e[36m"
END="\e[0m"

echo -e "${CYN}"
cat << EOF
╭──────────────────────────────────────────────────────────────────╮
│ TRL11 Work Dev Environment                                       │
├──────────────────────────────────────────────────────────────────┤
│ Quick commands:                                                  │
│ • make dev       - Start devcontainer                            │
│ • make dev-stop  - Stop devcontainer                             │
│ • make redev     - Restart devcontainer                          │
│ • make code      - Open VS Code in devcontainer                  │
├──────────────────────────────────────────────────────────────────┤
│ Host project directory:                                          │
│ ${CURRENT_DIR}$(printf '%*s' $((63 - ${#CURRENT_DIR})) '')  │
╰──────────────────────────────────────────────────────────────────╯

Devcontainer built: ${BUILD_DATE}

Welcome back ${USERNAME}!
EOF
echo -e "${END}"
