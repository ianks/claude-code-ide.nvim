#!/usr/bin/env bash

# Run tests for claude-code-ide.nvim
set -e

echo "Running claude-code-ide.nvim tests..."

# Check if plenary is available
if ! nvim --headless -c "lua require('plenary')" -c "q" 2>/dev/null; then
    echo "Error: plenary.nvim is required to run tests"
    echo "Install it with your package manager"
    exit 1
fi

# Run tests
nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"

echo "Tests completed!"