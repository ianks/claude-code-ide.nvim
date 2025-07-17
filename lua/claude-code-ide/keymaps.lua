-- Keymaps for claude-code-ide.nvim
-- Provides default keybindings following 2025 Neovim best practices

local M = {}

-- Setup keymaps based on configuration
---@param config table Keymaps configuration from main config
function M.setup(config)
	if not config.enabled then
		return
	end

	local prefix = config.prefix or "<leader>c"
	local mappings = config.mappings or {}

	-- Helper to create mapping with prefix
	local function map(key, action, desc, mode)
		mode = mode or "n"
		local lhs = prefix .. key
		vim.keymap.set(mode, lhs, action, {
			desc = desc,
			silent = true,
			noremap = true,
		})
	end

	-- Create which-key group if available
	local ok, which_key = pcall(require, "which-key")
	if ok then
		which_key.register({
			[prefix] = { name = "+claude" },
		})
	end

	-- Core mappings
	if mappings.toggle then
		map(mappings.toggle, function()
			local ui = require("claude-code-ide.ui")
			ui.toggle_conversation()
		end, "Toggle Claude conversation")
	end

	if mappings.send_selection then
		map(mappings.send_selection, function()
			local ui = require("claude-code-ide.ui")
			ui.send_selection()
		end, "Send selection to Claude", { "n", "v" })
	end

	if mappings.send_file then
		map(mappings.send_file, function()
			local ui = require("claude-code-ide.ui")
			ui.send_file()
		end, "Send file to Claude")
	end

	if mappings.send_diagnostics then
		map(mappings.send_diagnostics, function()
			local ui = require("claude-code-ide.ui")
			ui.send_diagnostics()
		end, "Send diagnostics to Claude")
	end

	if mappings.open_diff then
		map(mappings.open_diff, function()
			local ui = require("claude-code-ide.ui")
			ui.open_diff()
		end, "Open diff view")
	end

	if mappings.new_conversation then
		map(mappings.new_conversation, function()
			local ui = require("claude-code-ide.ui")
			ui.new_conversation()
		end, "Start new conversation")
	end

	if mappings.clear_conversation then
		map(mappings.clear_conversation, function()
			local ui = require("claude-code-ide.ui")
			ui.clear_conversation()
		end, "Clear conversation")
	end

	if mappings.retry_last then
		map(mappings.retry_last, function()
			local ui = require("claude-code-ide.ui")
			ui.retry_last()
		end, "Retry last message")
	end

	if mappings.show_palette then
		map(mappings.show_palette, function()
			local picker = require("claude-code-ide.ui.picker")
			picker.show_palette()
		end, "Show command palette")
	end

	if mappings.toggle_context then
		map(mappings.toggle_context, function()
			local layout = require("claude-code-ide.ui.layout")
			layout.toggle_context()
		end, "Toggle context pane")
	end

	if mappings.toggle_preview then
		map(mappings.toggle_preview, function()
			local layout = require("claude-code-ide.ui.layout")
			layout.toggle_preview()
		end, "Toggle preview pane")
	end

	if mappings.cycle_layout then
		map(mappings.cycle_layout, function()
			local layout = require("claude-code-ide.ui.layout")
			layout.cycle_preset()
		end, "Cycle layout preset")
	end

	-- Terminal mappings (if code execution is enabled)
	local code_exec_cfg = require("claude-code-ide.config").get("features.code_execution")
	if code_exec_cfg and code_exec_cfg.enabled then
		if mappings.execute_selection then
			map(mappings.execute_selection, function()
				local terminal = require("claude-code-ide.terminal")
				terminal.execute_selection()
			end, "Execute selection in terminal", "v")
		end

		if mappings.execute_buffer then
			map(mappings.execute_buffer, function()
				local terminal = require("claude-code-ide.terminal")
				terminal.execute_buffer()
			end, "Execute buffer in terminal")
		end

		if mappings.open_terminal then
			map(mappings.open_terminal, function()
				local terminal = require("claude-code-ide.terminal")
				terminal.open()
			end, "Open terminal")
		end
	end

	-- Quick action mappings
	local quick_actions = {
		{ key = "e", prompt = "Please explain this code", desc = "Explain code" },
		{ key = "i", prompt = "Please suggest improvements for this code", desc = "Suggest improvements" },
		{ key = "f", prompt = "Please fix the issues in this code", desc = "Fix code" },
		{ key = "t", prompt = "Please write tests for this code", desc = "Generate tests" },
		{ key = "d", prompt = "Please add documentation for this code", desc = "Add documentation" },
		{ key = "r", prompt = "Please refactor this code", desc = "Refactor code" },
	}

	for _, action in ipairs(quick_actions) do
		if mappings["quick_" .. action.key] ~= false then
			map(action.key, function()
				local ui = require("claude-code-ide.ui")
				ui.send_current()
				vim.defer_fn(function()
					ui.add_message("user", action.prompt)
				end, 100)
			end, action.desc, { "n", "v" })
		end
	end
end

-- Remove all keymaps
function M.remove(config)
	local prefix = config.prefix or "<leader>c"
	local mappings = config.mappings or {}

	-- Helper to remove mapping
	local function unmap(key, mode)
		mode = mode or "n"
		local lhs = prefix .. key
		pcall(vim.keymap.del, mode, lhs)
	end

	-- Remove all configured mappings
	for _, key in pairs(mappings) do
		if type(key) == "string" then
			unmap(key, "n")
			unmap(key, "v")
		end
	end

	-- Remove quick action mappings
	local quick_keys = { "e", "i", "f", "t", "d", "r" }
	for _, key in ipairs(quick_keys) do
		unmap(key, "n")
		unmap(key, "v")
	end
end

return M
