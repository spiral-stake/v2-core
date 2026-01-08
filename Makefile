# Store the server PID for cleanup
SERVER_PID_FILE := .server.pid

test: start-server test-flashLeverage stop-server

start-server:
	@echo "Starting swap-api server"
	@make test-base
	@ts-node api/index.ts & echo $$! > $(SERVER_PID_FILE)
	@sleep 2

test-base: 	
	@echo "Setting test base"
	forge test --match-path test/TestBase.t.sol --via-ir

test-flashLeverage:
	@echo "Testing FlashLeverage"
	forge test --match-path test/FlashLeverage.t.sol --via-ir -vvv

stop-server:
	@echo "Stopping swap-api server"
	@if [ -f $(SERVER_PID_FILE) ]; then \
		kill $$(cat $(SERVER_PID_FILE)) 2>/dev/null || true; \
		rm -f $(SERVER_PID_FILE); \
	fi
	@kill -9 $$(lsof -ti :3000) 2>/dev/null || true