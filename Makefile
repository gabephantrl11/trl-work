#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#

# -----------------------------------------------------------------------------
# Paths
# -----------------------------------------------------------------------------

DEVCONTAINER_DIR := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
DEVCONTAINER_DIR := $(patsubst %/,%,$(DEVCONTAINER_DIR))

TOOLS_DIR := $(DEVCONTAINER_DIR)/tools
WORKSPACE_DIR := $(abspath $(DEVCONTAINER_DIR)/..)

export WORKSPACE_DIR

# -----------------------------------------------------------------------------
# Includes
# -----------------------------------------------------------------------------

NO_DELEGATE_TARGETS := 1

include $(TOOLS_DIR)/maketools/logging.mk
include $(TOOLS_DIR)/maketools/help.mk
include $(DEVCONTAINER_DIR)/devcontainer.mk

# -----------------------------------------------------------------------------
# Repository management
# -----------------------------------------------------------------------------

REPO := $(TOOLS_DIR)/repo.sh

repos-%: ## Run command on all repos (repos-help for details)
	@$(REPO) $*

repo-%: ## Run command on single repo (e.g., repo-trl-viponly-report)
	@$(REPO) --single "$*"

# -----------------------------------------------------------------------------
# Install
# -----------------------------------------------------------------------------

INSTALL_TARGETS := .claude CLAUDE.md Makefile

install: ## Install trl-work devcontainer to work with this workspace
	@if [ "$(CURDIR)" != "$(DEVCONTAINER_DIR)" ]; then \
		echo "Error: install must be run from $(DEVCONTAINER_DIR)"; \
		exit 1; \
	fi
	@for target in $(INSTALL_TARGETS); do \
		ln -snf .devcontainer/$$target $(WORKSPACE_DIR)/$$target && \
		echo "Linked $(WORKSPACE_DIR)/$$target -> .devcontainer/$$target"; \
	done

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

help: ## Show available targets
	$(call list_targets,Workspace Management)
	$(call print_section,Repository Management)
	$(call print_item,repos-<cmd>,Run command on all repos)
	$(call print_item,repo-<name>-<cmd>,Run command on a single repo)
	$(call print_text,)
	$(call print_text,Run 'make repos-help' for available commands and options.)

.PHONY: help install
