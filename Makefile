# Store the server PID for cleanup
SERVER_PID_FILE := .server.pid

all: test-setup start-server test-flashLeverage stop-server

start-server:
	@echo "Starting swap-api server"
	@ts-node api/index.ts & echo $$! > $(SERVER_PID_FILE)
	@sleep 2

test-setup: 	
	@echo "Setting test setup"
	forge test --match-path test/Setup.t.sol --via-ir

test-flashLeverage:
	@echo "Testing FlashLeverage"
	forge test --match-path test/FlashLeverage.t.sol --via-ir -vv

test-flashLeverageCore:
	@echo "Testing FlashLeverageCore"
	forge test --match-path test/FlashLeverageCore.t.sol --via-ir -vv

stop-server:
	@echo "Stopping swap-api server"
	@if [ -f $(SERVER_PID_FILE) ]; then \
		kill $$(cat $(SERVER_PID_FILE)) 2>/dev/null || true; \
		rm -f $(SERVER_PID_FILE); \
	fi
	@kill -9 $$(lsof -ti :3000) 2>/dev/null || true

# Handle cleanup on interrupt (Ctrl+C)
.PHONY: cleanup
cleanup:
	@echo "Terminating processes on port 3000..."
	@kill -9 $$(lsof -ti :3000) || true
	@rm -f $(SERVER_PID_FILE)

# Trap SIGINT and call cleanup
.PHONY: start
start:
	@trap '$(MAKE) cleanup; exit' INT; \
	$(MAKE) all

# Override the default target
.DEFAULT_GOAL := start

.PHONY: all start-server test-setup test-flashLeverage test-flashLeverageCore stop-server cleanup start