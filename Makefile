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

repo-%: ## Repo management (repo-help for details)
	@$(REPO) $*

help: ## Show available targets
	$(call list_targets,Workspace Management)
	$(call print_section,Repository Management)
	$(call print_text,All repo-* targets delegate to tools/repo.sh.)
	$(call print_text,Run make repo-help for commands and options.)

.PHONY: help
