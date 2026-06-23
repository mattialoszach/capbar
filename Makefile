APP_NAME    := CapBar
DIST_APP    := dist/$(APP_NAME).app
INSTALL_DIR := /Applications
TARGET_APP  := $(INSTALL_DIR)/$(APP_NAME).app
PKG_SCRIPT  := scripts/package_app.sh

.DEFAULT_GOAL := help

.PHONY: help build install update run reinstall uninstall clean

help: ## Show available targets
	@echo "CapBar — available make targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| sort \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build CapBar.app into ./dist
	@chmod +x $(PKG_SCRIPT)
	@$(PKG_SCRIPT) >/dev/null
	@echo "Built $(DIST_APP)"

run: build ## Build, then launch the freshly built app from ./dist
	@open "$(DIST_APP)"

update: ## Pull latest, rebuild, and install the update into /Applications
	@echo "==> Fetching latest changes…"
	@git pull --ff-only
	@$(MAKE) build
	@$(MAKE) install

install: build ## Install the built app into /Applications (asks before replacing)
	@if [ ! -d "$(DIST_APP)" ]; then \
		echo "error: $(DIST_APP) not found. Run 'make build' first." >&2; exit 1; \
	fi
	@if [ -d "$(TARGET_APP)" ]; then \
		installed=$$(defaults read "$(TARGET_APP)/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown"); \
		built=$$(defaults read "$$(pwd)/$(DIST_APP)/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "unknown"); \
		echo "$(APP_NAME) is already installed in $(INSTALL_DIR) (version $$installed)."; \
		echo "Newly built version: $$built"; \
		printf "Replace the installed copy with the new build? [y/N] "; \
		read ans; \
		case "$$ans" in \
			[yY]|[yY][eE][sS]) ;; \
			*) echo "Aborted. Installed app left unchanged."; exit 0;; \
		esac; \
		echo "==> Quitting running $(APP_NAME)…"; \
		osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || true; \
		pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true; \
		sleep 1; \
		echo "==> Removing old $(TARGET_APP)…"; \
		rm -rf "$(TARGET_APP)"; \
	fi
	@echo "==> Installing to $(TARGET_APP)…"
	@cp -R "$(DIST_APP)" "$(TARGET_APP)"
	@echo "==> Launching $(APP_NAME)…"
	@open "$(TARGET_APP)"
	@echo "Done. $(APP_NAME) is installed in $(INSTALL_DIR)."

reinstall: ## Force reinstall without rebuilding (uses existing ./dist build)
	@$(MAKE) install

uninstall: ## Quit and remove CapBar from /Applications
	@osascript -e 'tell application "$(APP_NAME)" to quit' >/dev/null 2>&1 || true
	@pkill -x "$(APP_NAME)" >/dev/null 2>&1 || true
	@if [ -d "$(TARGET_APP)" ]; then \
		rm -rf "$(TARGET_APP)"; \
		echo "Removed $(TARGET_APP)."; \
	else \
		echo "$(APP_NAME) is not installed in $(INSTALL_DIR)."; \
	fi

clean: ## Remove build artifacts (.build and dist)
	@rm -rf .build dist
	@echo "Cleaned .build and dist."
