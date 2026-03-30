#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#

DEVCONTAINER_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
DEVCONTAINER_DIR := $(patsubst %/,%,$(DEVCONTAINER_DIR))

TOOLS_DIR := $(DEVCONTAINER_DIR)/tools
WORKSPACE_DIR := $(abspath $(DEVCONTAINER_DIR)/..)

export WORKSPACE_DIR

NO_DELEGATE_TARGETS := 1

include $(TOOLS_DIR)/maketools/logging.mk
include $(TOOLS_DIR)/maketools/help.mk
include $(DEVCONTAINER_DIR)/devcontainer.mk

REPO := $(TOOLS_DIR)/repo.sh

repos-%: ## Run command on all repos (repos-help for details)
	@$(REPO) $*

repo-%: ## Run command on single repo (e.g., repo-trl-viponly-report)
	@$(REPO) --single "$*"

help: ## Show available targets
	$(call list_targets,Workspace Management)
	$(call print_section,Repository Management)
	$(call print_text,repos-* runs on all repos$(,) repo-<name>-<cmd> runs on one.)
	$(call print_text,Run make repos-help for commands and options.)

.PHONY: help
