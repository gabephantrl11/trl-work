#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#

# =============================================================================
# Usage:
# Include this file in your Makefile:
#   include devtools/maketools/help.mk
#
# Option 1: Use the macro in your help target
#   help:
#   	$(call list_targets)
#   	@printf "\n$(LOG_BLUE)Applications:$(LOG_NC)\n"
#   	@printf "  $(LOG_GREEN)%-15s$(LOG_NC) %s\n" "my-app" "Description"
#
# Option 2: Use the macro with a custom header
#   help:
#   	$(call list_targets,Build Targets)
#
# Option 3: List targets from specific files only
#   help:
#   	$(call list_targets_from,server/Makefile,Server Targets)
#   	$(call list_targets_from,sdk/Makefile,SDK Targets)
#
# Targets should be documented with ## comments:
#   build: deps  ## Build the project
#   test:        ## Run all tests
#   clean:       ## Remove build artifacts
# =============================================================================

# Requires logging.mk for color definitions
# If not included, define defaults
LOG_BLUE ?= \033[0;94m
LOG_GREEN ?= \033[0;32m
LOG_NC ?= \033[0m

# Comma and space variables for use in $(call ...) arguments
, := ,
empty :=
space := $(empty) $(empty)

# -----------------------------------------------------------------------------
# list_targets - List all documented targets from MAKEFILE_LIST
#
# Arguments:
#   $(1) - Optional header text (default: "Targets")
#
# Example:
#   $(call list_targets)
#   $(call list_targets,Available Commands)
# -----------------------------------------------------------------------------
define list_targets
	@awk 'BEGIN { \
		FS = ":.*##"; \
		printf "\n$(LOG_BLUE)Usage:$(LOG_NC)\n  make <target>\n\n"; \
		printf "$(LOG_BLUE)$(if $(1),$(1),Targets):$(LOG_NC)\n" \
	} \
	/^[a-zA-Z_0-9-]+:.*?##/ { \
		printf "  $(LOG_GREEN)%-20s$(LOG_NC) %s\n", $$1, $$2 \
	}' $(MAKEFILE_LIST)
endef

# -----------------------------------------------------------------------------
# list_targets_from - List documented targets from a specific file
#
# Arguments:
#   $(1) - File path to scan for targets
#   $(2) - Optional header text (default: "Targets")
#
# Example:
#   $(call list_targets_from,server/Makefile)
#   $(call list_targets_from,sdk/Makefile,SDK Targets)
# -----------------------------------------------------------------------------
define list_targets_from
	@awk 'BEGIN { \
		FS = ":.*##"; \
		printf "\n$(LOG_BLUE)$(if $(2),$(2),Targets):$(LOG_NC)\n" \
	} \
	/^[a-zA-Z_0-9-]+:.*?##/ { \
		printf "  $(LOG_GREEN)%-20s$(LOG_NC) %s\n", $$1, $$2 \
	}' $(1)
endef

# -----------------------------------------------------------------------------
# list_targets_from_single - List targets with single # comments from a file
#
# Use this for targets when you don't want to show all the targets when it is
# included in a top level Makefile help target but you still want to show them
# when called directly.  You can add to the help target of the sub-Makefile.
#
# Arguments:
#   $(1) - File path to scan for targets
#   $(2) - Optional header text (default: "Targets")
#
# Example:
#   $(call list_targets_from_single,tools/local.mk,Local Targets)
# -----------------------------------------------------------------------------
define list_targets_from_single
	@awk 'BEGIN { \
		FS = ":[ \t]*#[ \t]*"; \
		printf "\n$(LOG_BLUE)$(if $(2),$(2),Targets):$(LOG_NC)\n" \
	} \
	/^[a-zA-Z_0-9-]+:[ \t]*#[^#]/ { \
		printf "  $(LOG_GREEN)%-20s$(LOG_NC) %s\n", $$1, $$2 \
	}' $(1)
endef

# -----------------------------------------------------------------------------
# list_targets_no_header - List targets without any header (for combining)
#
# Arguments:
#   $(1) - Optional file path (default: MAKEFILE_LIST)
#
# Example:
#   @printf "$(LOG_BLUE)All Targets:$(LOG_NC)\n"
#   $(call list_targets_no_header)
# -----------------------------------------------------------------------------
define list_targets_no_header
	@awk 'BEGIN { FS = ":.*##" } \
	/^[a-zA-Z_0-9-]+:.*?##/ { \
		printf "  $(LOG_GREEN)%-20s$(LOG_NC) %s\n", $$1, $$2 \
	}' $(if $(1),$(1),$(MAKEFILE_LIST))
endef

# -----------------------------------------------------------------------------
# print_item - Helper to print a name/description entry consistently
#
# Arguments:
#   $(1) - Item name
#   $(2) - Description
#
# Example:
#   $(call print_item,xcng-server,gRPC video server)
#   $(call print_item,server-<target>,Run target in server/)
# -----------------------------------------------------------------------------
define print_item
	@printf "  $(LOG_GREEN)%-20s$(LOG_NC) %s\n" "$(1)" "$(2)"
endef

# -----------------------------------------------------------------------------
# print_section - Print a section header
#
# Arguments:
#   $(1) - Section title
#
# Example:
#   $(call print_section,Applications)
# -----------------------------------------------------------------------------
define print_section
	@printf "\n$(LOG_BLUE)$(1):$(LOG_NC)\n"
endef

# -----------------------------------------------------------------------------
# print_var - Print an environment variable entry
#
# Arguments:
#   $(1) - Variable name
#   $(2) - Description
#
# Example:
#   $(call print_var,BUILD_JOBS,Number of parallel build jobs)
# -----------------------------------------------------------------------------
define print_var
	@printf "  $(LOG_GREEN)%-20s$(LOG_NC) %s\n" "$(1)" "$(2)"
endef

# -----------------------------------------------------------------------------
# print_example - Print an example line (no formatting)
#
# Arguments:
#   $(1) - Example text
#
# Example:
#   $(call print_example,make build BUILD_PROFILE=debug)
# -----------------------------------------------------------------------------
define print_example
	@printf "  %s\n" "$(1)"
endef

# -----------------------------------------------------------------------------
# print_text - Print plain text (for explanations)
#
# Arguments:
#   $(1) - Text to print
#
# Example:
#   $(call print_text,Use <component>-<target> to run targets in subprojects)
# -----------------------------------------------------------------------------
define print_text
	@printf "  %s\n" "$(1)"
endef

# -----------------------------------------------------------------------------
# print_text_raw - Print raw text without indentation
#
# Arguments:
#   $(1) - Text to print
#
# Example:
#   $(call print_text_raw,Some raw text)
# -----------------------------------------------------------------------------
define print_text_raw
	@printf "%s\n" "$(1)"
endef

# -----------------------------------------------------------------------------
# print_newline - Print an empty line
#
# Example:
#   $(call print_newline)
# -----------------------------------------------------------------------------
define print_newline
	@printf "\n"
endef

# =============================================================================
# Auto-Delegate Targets
#
# Automatically generate delegate targets for subdirectories with Makefiles.
# This enables patterns like: make <subdir>-<target>
#
# Usage:
#   # Option 1: Auto-detect subdirectories with Makefiles
#   DELEGATE_AUTO := 1
#
#   # Option 2: Explicit list (simple names use same directory)
#   DELEGATE_DIRS := client controller frontend server
#
#   # Option 3: Custom paths using name=path format
#   DELEGATE_DIRS += docs=docs/dev vimba-cli=tools/vimba-cli
#
#   # Include help.mk (after defining DELEGATE_AUTO or DELEGATE_DIRS)
#   include devtools/maketools/help.mk
#
# Recursive delegation works automatically:
#   make sdk-cpp-build      -> sdk/cpp/Makefile build target
#   make server-tests-test  -> server/tests/Makefile test target
# =============================================================================

# Auto-detect subdirectories with Makefiles (enabled by default)
# Set NO_DELEGATE_TARGETS=1 to disable automatic delegation
ifndef NO_DELEGATE_TARGETS
  # Find all immediate subdirectories containing a Makefile
  _auto_delegate_dirs := $(patsubst %/Makefile,%,$(wildcard */Makefile))
  # Append to any existing DELEGATE_DIRS
  DELEGATE_DIRS += $(_auto_delegate_dirs)
endif

# Generate delegate pattern rules for each entry in DELEGATE_DIRS
# Supports both "name" (dir=name) and "name=path" formats
ifdef DELEGATE_DIRS

# Extract name from "name" or "name=path"
_delegate_name = $(firstword $(subst =, ,$(1)))
# Extract path from "name" or "name=path" (defaults to name if no =)
_delegate_path = $(or $(word 2,$(subst =, ,$(1))),$(1))

define make_delegate_rule
.PHONY: $(call _delegate_name,$(1))-%
$(call _delegate_name,$(1))-%:
	$$(call log_section,$$* $(call _delegate_name,$(1)))
	$$(Q)$$(MAKE) $$(PRINT_DIR) -C $(call _delegate_path,$(1)) $$*
endef

$(foreach entry,$(DELEGATE_DIRS),$(eval $(call make_delegate_rule,$(entry))))
endif

# =============================================================================
# Default help target (optional)
# Uncomment the following lines if your Makefile doesn't define its own help:
#
#   .PHONY: help
#   help: ## Display this help message
#   	$(call list_targets)
#
# Or for Makefiles that define their own help, simply call the macro:
#   help: ## Display this help message
#   	$(call list_targets)
#   	$(call print_section,My Custom Section)
#   	$(call print_item,my-app,Description)
# =============================================================================
