-- Minimal init.lua for running tests
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"

-- Set up package path
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
local plugin_path = vim.fn.getcwd()

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(plugin_path)

-- Load required plugins
vim.cmd("runtime! plugin/plenary.vim")

-- Configure Neovim for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.hidden = true

-- Set up globals for testing
_G.__TEST = true

-- Ensure required modules are loaded
require("plenary.busted")