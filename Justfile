# Justfile for claude-code-ide.nvim

# Default recipe
default:
    @just --list

# Run all tests (unit + integration)
test: test-unit test-integration
    @echo "All tests passed!"

# Run unit tests only
test-unit:
    @./scripts/test-runner.lua

# Run tests with output
test-verbose:
    nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"

# Run a specific test file
test-file FILE:
    nvim --headless -u tests/minimal_init.lua -c "lua require('plenary.busted').run('{{FILE}}')" -c "qa!"

# Run WebSocket tests
test-websocket:
    just test-file tests/spec/server/websocket_spec.lua

# Check code with luacheck (if installed)
lint:
    @command -v luacheck >/dev/null 2>&1 && luacheck lua/ || echo "luacheck not installed"

# Type check with lua-language-server
typecheck:
    @command -v lua-language-server >/dev/null 2>&1 && lua-language-server --check . || echo "lua-language-server not installed - run 'nix develop'"

# Format code with stylua (if installed)
format:
    @command -v stylua >/dev/null 2>&1 && stylua lua/ tests/ || echo "stylua not installed"

# Format all files with treefmt
fmt:
    @command -v treefmt >/dev/null 2>&1 && treefmt || echo "treefmt not installed - run 'nix develop' or 'nix fmt'"

# Check formatting with treefmt
fmt-check:
    @command -v treefmt >/dev/null 2>&1 && treefmt --fail-on-change || echo "treefmt not installed - run 'nix develop'"

# Run integration tests
test-integration:
    @./scripts/integration-test-runner.lua

# Run specific integration test file
test-integration-file FILE:
    nvim --headless -u tests/integration_init.lua -c "lua require('plenary.busted').run('{{FILE}}')" -c "qa!"


# Run all checks (tests, lint, format check, typecheck)
check: test lint typecheck fmt-check

# Clean any generated files
clean:
    rm -f ~/.claude/ide/*.lock

# Start development server (when implemented)
dev:
    nvim -c "lua require('claude-code-ide').setup({ debug = true })"

# Install dependencies (for development)
deps:
    @echo "Ensure these Neovim plugins are installed:"
    @echo "- plenary.nvim"
    @echo "- nvim-nio"
    @echo "- snacks.nvim"
    @echo "- nui.nvim (optional)"

# Run example configuration
example NAME="basic":
    nvim -u examples/{{NAME}}/init.lua
