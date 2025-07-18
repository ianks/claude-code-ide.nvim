-- Simple keymaps for claude-code-ide.nvim
-- Provides basic keybindings without complex UI dependencies

local M = {}

-- Setup all keymaps
---@param opts table? Optional keymap configuration
function M.setup(opts)
	opts = opts or {}

	-- Don't set up keymaps if explicitly disabled
	if opts == false then
		return
	end

	-- Default keymap configuration
	local defaults = {
		prefix = "<leader>c",
	}

	local config = vim.tbl_deep_extend("force", defaults, opts)

	-- Register which-key group if available
	local ok, which_key = pcall(require, "which-key")
	if ok then
		which_key.add({
			{ config.prefix, group = "Claude Code" },
			{ config.prefix .. "c", group = "Code" },
		})
	end

	-- Define keymaps
	local keymaps = {
		-- Server control
		{ "n", config.prefix .. "s", "<cmd>ClaudeCode start<CR>", "Start Claude Code server" },
		{ "n", config.prefix .. "S", "<cmd>ClaudeCode stop<CR>", "Stop Claude Code server" },
		{ "n", config.prefix .. "?", "<cmd>ClaudeCode status<CR>", "Show Claude Code status" },
		{ "n", config.prefix .. "o", "<cmd>ClaudeCodeConnect<CR>", "Connect Claude to Neovim" },
	}

	-- Set keymaps
	for _, keymap in ipairs(keymaps) do
		local mode, lhs, rhs, desc = unpack(keymap)
		vim.keymap.set(mode, lhs, rhs, {
			desc = "Claude Code: " .. desc,
			silent = true,
		})
	end
	
	-- Setup text object keymaps
	local ok, text_objects = pcall(require, "claude-code-ide.text_objects")
	if ok then
		text_objects.setup_keymaps()
	end
end

return M