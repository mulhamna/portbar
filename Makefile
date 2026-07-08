# PortBar — dev / test shortcuts
# Usage: `make run`, `make smoke`, `make test-ports`, `make stop`

PROJECT   := PortBar.xcodeproj
SCHEME    := PortBar
DERIVED   := build
APP       := $(DERIVED)/Build/Products/Debug/PortBar.app

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

.PHONY: check-xcode
check-xcode: ## Verify full Xcode is selected (not just CLT)
	@xcodebuild -version >/dev/null 2>&1 || { \
		echo "✗ Full Xcode required. Run:"; \
		echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"; \
		exit 1; }
	@echo "✓ $$(xcodebuild -version | head -1)"

.PHONY: build
build: check-xcode ## Build Debug into ./build
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(DERIVED) build

.PHONY: run
run: build stop ## Build, launch, confirm alive
	open $(APP)
	@sleep 1; pgrep -x PortBar >/dev/null && echo "✓ PortBar running (⚡ in menu bar)" || echo "✗ not running"

.PHONY: stop
stop: ## Kill any running PortBar instance
	@pkill -x PortBar 2>/dev/null || true

.PHONY: test-ports
test-ports: ## Spawn 3 test servers (local, LAN-exposed, Vite range)
	@python3 -m http.server 8888 --bind 127.0.0.1 >/dev/null 2>&1 & echo "  :8888  local-only  → expect NO antenna, globe present"
	@python3 -m http.server 8890 --bind 0.0.0.0   >/dev/null 2>&1 & echo "  :8890  LAN-exposed → expect ORANGE antenna + globe"
	@python3 -m http.server 5173                  >/dev/null 2>&1 & echo "  :5173  Vite range  → expect globe present (bug #3)"
	@echo "Click the ⚡ menu bar icon and verify. Then: make kill-ports"

.PHONY: kill-ports
kill-ports: ## Kill the test servers
	@pkill -f "http.server" 2>/dev/null || true
	@echo "test servers killed"

.PHONY: smoke
smoke: run test-ports ## Full smoke: build, run, spawn test ports
	@echo ""
	@echo "Manual checks:"
	@echo "  1. :8890 shows orange antenna 📡, :8888 does not"
	@echo "  2. :5173 shows globe button"
	@echo "  3. Turn Watch OFF, click ✕ on a row → row vanishes <1s (bug #1)"
	@echo "  4. ⚡ count drops when you run 'make kill-ports'"

.PHONY: release
release: check-xcode ## Build Release configuration
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(DERIVED) build

.PHONY: clean
clean: ## Remove build output
	rm -rf $(DERIVED)
