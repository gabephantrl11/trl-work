#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#

# =============================================================================
# Usage:
# Include this file in your Makefile:
#   include devtools/maketools/logging.mk
#
# Then use the logging macros:
#   $(call log_info,"Starting build process")
#   $(call log_warn,"Dependency X not found, using default")
#   $(call log_error,"Build failed: missing required files")
#   $(call log_section,"Section Header")
# =============================================================================

# Color definitions
LOG_RED := \033[0;31m
LOG_GREEN := \033[0;32m
LOG_YELLOW := \033[0;33m
LOG_PURPLE := \033[0;35m
LOG_ORANGE := \033[38;2;255;165;0m
LOG_BLUE := \033[0;94m
LOG_GRAY := \033[0;90m
LOG_NC := \033[0m  # No Color

LOG_SECTION_COLOR ?= $(LOG_BLUE)

# Logging macros
define log_info
	@printf "$(LOG_GREEN)[INFO] $(1)$(LOG_NC)\n"
endef

define log_warn
	@printf "$(LOG_YELLOW)[WARN] $(1)$(LOG_NC)\n"
endef

define log_error
	@printf "$(LOG_RED)[ERROR] $(1)$(LOG_NC)\n"
endef

define log_section
	@printf "$(LOG_SECTION_COLOR)"
	@printf "================================================================================\n"
	@printf "$(1)\n"
	@printf "================================================================================"
	@printf "$(LOG_NC)\n"
endef

# Shell function macros (for use within shell commands)
define show_info
printf "$(LOG_GREEN)[INFO] %s$(LOG_NC)\n" "$(1)"
endef

define show_warn
printf "$(LOG_YELLOW)[WARN] %s$(LOG_NC)\n" "$(1)"
endef

define show_error
printf "$(LOG_RED)[ERROR] %s$(LOG_NC)\n" "$(1)"
endef

define show_section
	printf "$(LOG_GRAY)"; \
	printf "═════════════════════════════════════════════════════════════════════════\n"; \
	printf "$(1)\n"; \
	printf "═════════════════════════════════════════════════════════════════════════"; \
	printf "$(LOG_NC)\n"
endef
