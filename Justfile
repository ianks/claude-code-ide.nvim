# Justfile for claude-code.nvim

# Default recipe
default:
    @just --list

# Run all tests
test:
    nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}" -c "qa!"

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

# Format code with stylua (if installed)
format:
    @command -v stylua >/dev/null 2>&1 && stylua lua/ tests/ || echo "stylua not installed"

# Clean any generated files
clean:
    rm -f ~/.claude/ide/*.lock

# Start development server (when implemented)
dev:
    nvim -c "lua require('claude-code').setup({ debug = true })"

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