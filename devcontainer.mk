#
# Copyright (c) 2025 TRL11, Inc.  All rights reserved.
#

PROJ_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))
PROJ_ROOT := $(patsubst %/,%,$(PROJ_ROOT))

WORKSPACE_NAME = trl-work
DEVCONTAINER_HASH := $(shell printf '%s' "$(PROJ_ROOT)" | md5sum | cut -c1-8)
DEVCONTAINER_NAME := $(WORKSPACE_NAME)-$(DEVCONTAINER_HASH)
export DEVCONTAINER_NAME

ifeq ($(HOST_USER),)
HOST_USER := $(shell whoami)
endif

ifeq ($(HOST_NAME),)
HOST_NAME := $(shell hostname)
endif

# Set rebuild flag based on REBUILD variable
ifeq ($(REBUILD),1)
REBUILD_FLAG := --build-no-cache
$(info Force rebuilding devcontainer...)
else
REBUILD_FLAG :=
endif

# Set verbose flags based on VERBOSE variable
ifeq ($(VERBOSE),1)
VERBOSE_FLAGS := --log-level trace
$(info Verbose mode enabled...)
else
VERBOSE_FLAGS :=
endif

DEVCONTAINER_CONFIG = $(PROJ_ROOT)/.devcontainer/devcontainer.json

# Docker filter to find this project's devcontainer
DEVCONTAINER_FILTER = label=devcontainer.local_folder=$(PROJ_ROOT)

# Check if devcontainer is already running or start a new one
devcontainer-start:
	@if ! command -v devcontainer >/dev/null 2>&1; then \
		echo "\e[31mDevcontainer CLI is required. Install with: npm install -g @devcontainers/cli\e[0m"; \
		exit 1; \
	fi
	@if [ ! -d $(HOME)/.npm ]; then \
		mkdir -p $(HOME)/.npm; \
	fi
	@if ! docker ps --filter "$(DEVCONTAINER_FILTER)" --format "{{.ID}}" | grep -q .; then \
		echo "Starting devcontainer..."; \
		devcontainer up $(REBUILD_FLAG) $(VERBOSE_FLAGS) \
			--workspace-folder $(PROJ_ROOT) \
			--config $(DEVCONTAINER_CONFIG) & \
		DC_PID=$$!; \
		while ! docker ps --filter "$(DEVCONTAINER_FILTER)" --format "{{.ID}}" | grep -q .; do \
			if ! kill -0 $$DC_PID 2>/dev/null; then \
				echo "\e[31mDevcontainer failed to start\e[0m"; \
				exit 1; \
			fi; \
			sleep 1; \
		done; \
		sleep 1; \
		kill $$DC_PID 2>/dev/null; wait $$DC_PID 2>/dev/null || true; \
		echo "Container ready"; \
	fi
	@CONTAINER_ID=$$(docker ps --filter "$(DEVCONTAINER_FILTER)" --format "{{.ID}}" | head -1); \
	docker exec -it -u dev -w /workspaces/$(WORKSPACE_NAME) \
		$$CONTAINER_ID \
		bash --init-file /workspaces/$(WORKSPACE_NAME)/.devcontainer/devcontainer.entrypoint.sh

# Stop and remove the devcontainer
devcontainer-stop:
	@CONTAINER_ID=$$(docker ps --filter "$(DEVCONTAINER_FILTER)" --format "{{.ID}}" | head -1); \
	if [ -n "$$CONTAINER_ID" ]; then \
		echo "Stopping devcontainer $$CONTAINER_ID"; \
		docker stop $$CONTAINER_ID; \
		docker rm $$CONTAINER_ID; \
		echo "Devcontainer stopped and removed"; \
	else \
		echo "No running devcontainer found"; \
	fi

dev: ## Start devcontainer in terminal
	@if [ "$(TRL11_DEV_CONTAINER)" = "true" ]; then \
		echo ""; \
		echo "\e[32mAlready in dev container\e[0m"; \
	else \
		$(MAKE) --no-print-directory devcontainer-start; \
	fi

dev-stop: devcontainer-stop ## Stop devcontainer and cleanup
	@rm -f .devcontainer/.env

redev: dev-stop dev ## Stop and restart devcontainer

code: ## Open VS Code in devcontainer
	@if [ "$(TRL11_DEV_CONTAINER)" = "true" ]; then \
		echo "\e[33mAlready in dev container - VS Code should already be connected\e[0m"; \
	else \
		echo "\e[36mOpening VS Code in devcontainer...\e[0m"; \
		devcontainer open --config $(DEVCONTAINER_CONFIG) $(PROJ_ROOT); \
	fi
