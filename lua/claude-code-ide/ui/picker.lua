-- Picker integration for claude-code-ide.nvim
-- Provides advanced command palette and selection features using snacks.nvim

local M = {}
local notify = require("claude-code-ide.ui.notify")

-- Command definitions with metadata
local commands = {
	-- Conversation commands
	{
		text = "Send Selection/File",
		value = "send_current",
		icon = "📤",
		desc = "Send current selection or file to Claude",
		action = function()
			require("claude-code-ide.ui").send_current()
		end,
	},
	{
		text = "Send Diagnostics",
		value = "diagnostics",
		icon = "🔍",
		desc = "Send LSP diagnostics to Claude",
		action = function()
			require("claude-code-ide.ui").show_diagnostics()
		end,
	},
	{
		text = "Clear Conversation",
		value = "clear",
		icon = "🗑️",
		desc = "Clear the current conversation",
		action = function()
			require("claude-code-ide.ui").clear_conversation()
		end,
	},
	{
		text = "New Conversation",
		value = "new",
		icon = "✨",
		desc = "Start a new conversation",
		action = function()
			require("claude-code-ide.ui").new_conversation()
		end,
	},
	{
		text = "Retry Last Request",
		value = "retry",
		icon = "🔄",
		desc = "Retry the last request to Claude",
		action = function()
			require("claude-code-ide.ui").retry_last()
		end,
	},
	-- Window commands
	{
		text = "Toggle Conversation Window",
		value = "toggle",
		icon = "🪟",
		desc = "Toggle the Claude conversation window",
		action = function()
			require("claude-code-ide.ui").toggle_conversation()
		end,
	},
	{
		text = "Show Notification History",
		value = "history",
		icon = "📜",
		desc = "Show notification history",
		action = function()
			notify.history()
		end,
	},
	-- Diff commands
	{
		text = "Open Diff View",
		value = "diff",
		icon = "📊",
		desc = "Open a diff view for suggested changes",
		action = function()
			-- TODO: Implement diff picker
			notify.info("Diff view coming soon!")
		end,
	},
	{
		text = "Close All Diffs",
		value = "close_diffs",
		icon = "❌",
		desc = "Close all open diff tabs",
		action = function()
			local tools = require("claude-code-ide.tools")
			tools.execute("closeAllDiffTabs", {})
		end,
	},
	-- Cache commands
	{
		text = "Cache Statistics",
		value = "cache_stats",
		icon = "📈",
		desc = "Show cache statistics",
		action = function()
			vim.cmd("ClaudeCodeCacheStats")
		end,
	},
	{
		text = "Clear Cache",
		value = "cache_clear",
		icon = "🧹",
		desc = "Clear all caches",
		action = function()
			vim.cmd("ClaudeCodeCacheClear")
		end,
	},
	-- Server commands
	{
		text = "Server Status",
		value = "status",
		icon = "📊",
		desc = "Show detailed server status",
		action = function()
			vim.cmd("ClaudeCodeStatus")
		end,
	},
	{
		text = "Restart Server",
		value = "restart",
		icon = "🔄",
		desc = "Restart the MCP server",
		action = function()
			vim.cmd("ClaudeCodeRestart")
		end,
	},
	{
		text = "Stop Server",
		value = "stop",
		icon = "🛑",
		desc = "Stop the MCP server",
		action = function()
			require("claude-code-ide").stop()
		end,
	},
	-- Log commands
	{
		text = "View Logs",
		value = "logs",
		icon = "📋",
		desc = "View Claude Code logs",
		action = function()
			vim.cmd("ClaudeCodeLog")
		end,
	},
	{
		text = "Tail Logs",
		value = "tail",
		icon = "📜",
		desc = "Tail the last 50 log entries",
		action = function()
			vim.cmd("ClaudeCodeLogTail")
		end,
	},
	{
		text = "Set Log Level",
		value = "log_level",
		icon = "🎚️",
		desc = "Change the log level",
		action = function()
			M.pick_log_level()
		end,
	},
	-- Layout commands
	{
		text = "Change Layout",
		value = "layout",
		icon = "🎨",
		desc = "Switch between different UI layouts",
		action = function()
			M.pick_layout()
		end,
	},
	{
		text = "Toggle Context Pane",
		value = "context",
		icon = "📋",
		desc = "Show/hide the context information pane",
		action = function()
			require("claude-code-ide.ui").toggle_context()
		end,
	},
	{
		text = "Toggle Preview Pane",
		value = "preview",
		icon = "👁️",
		desc = "Show/hide the preview pane",
		action = function()
			require("claude-code-ide.ui").toggle_preview()
		end,
	},
	-- Code actions
	{
		text = "Extract Selection to Function",
		value = "extract_function",
		icon = "🔧",
		desc = "Ask Claude to extract selection to a function",
		action = function()
			local ui = require("claude-code-ide.ui")
			local mode = vim.fn.mode()
			if mode == "v" or mode == "V" then
				ui.send_current()
				vim.defer_fn(function()
					ui.add_message("user", "Please extract this selection to a function")
				end, 100)
			else
				notify.warn("Please select code to extract first")
			end
		end,
	},
	{
		text = "Explain Selection",
		value = "explain",
		icon = "💡",
		desc = "Ask Claude to explain the selected code",
		action = function()
			local ui = require("claude-code-ide.ui")
			local mode = vim.fn.mode()
			if mode == "v" or mode == "V" then
				ui.send_current()
				vim.defer_fn(function()
					ui.add_message("user", "Please explain this code")
				end, 100)
			else
				notify.warn("Please select code to explain first")
			end
		end,
	},
	{
		text = "Suggest Improvements",
		value = "improve",
		icon = "✨",
		desc = "Ask Claude to suggest improvements",
		action = function()
			local ui = require("claude-code-ide.ui")
			ui.send_current()
			vim.defer_fn(function()
				ui.add_message("user", "Please suggest improvements for this code")
			end, 100)
		end,
	},
}

-- Show the main command palette
function M.show_commands()
	local Snacks = require("snacks")

	Snacks.picker({
		source = "custom",
		title = " Claude Code Commands ",
		items = commands,
		format = function(item)
			return {
				text = {
					{ item.icon .. "  ", "SnacksPickerIcon" },
					{ item.text, "SnacksPickerItem" },
					{ "  " .. item.desc, "SnacksPickerComment" },
				},
			}
		end,
		confirm = function(picker, item)
			if item and item.action then
				item.action()
			end
		end,
		win = {
			input = {
				keys = {
					["?"] = {
						function(self)
							notify.info("Type to filter commands • Enter to execute • Esc to cancel")
						end,
						desc = "Show help",
					},
				},
			},
		},
	})
end

-- Pick a log level
function M.pick_log_level()
	local Snacks = require("snacks")
	local log = require("claude-code-ide.log")

	local levels = {
		{ text = "TRACE", icon = "🔍", desc = "Most verbose logging" },
		{ text = "DEBUG", icon = "🐛", desc = "Debug information" },
		{ text = "INFO", icon = "ℹ️", desc = "General information" },
		{ text = "WARN", icon = "⚠️", desc = "Warnings only" },
		{ text = "ERROR", icon = "❌", desc = "Errors only" },
		{ text = "OFF", icon = "🔇", desc = "Disable logging" },
	}

	Snacks.picker({
		source = "custom",
		title = " Select Log Level ",
		items = levels,
		format = function(item)
			local current = log.get_level()
			local prefix = item.text == current and "● " or "  "
			return {
				text = {
					{ prefix, "SnacksPickerSpecial" },
					{ item.icon .. "  ", "SnacksPickerIcon" },
					{ item.text, "SnacksPickerItem" },
					{ "  " .. item.desc, "SnacksPickerComment" },
				},
			}
		end,
		confirm = function(picker, item)
			if item then
				log.set_level(item.text)
				notify.info("Log level set to " .. item.text)
			end
		end,
	})
end

-- Pick a layout preset
function M.pick_layout()
	local Snacks = require("snacks")
	local ui = require("claude-code-ide.ui")
	local layout = require("claude-code-ide.ui.layout")

	local layouts = {
		{
			text = "Default",
			value = "default",
			icon = "📐",
			desc = "Conversation on right side",
		},
		{
			text = "Split",
			value = "split",
			icon = "🔲",
			desc = "Conversation + context pane",
		},
		{
			text = "Full",
			value = "full",
			icon = "🖥️",
			desc = "All panes visible",
		},
		{
			text = "Compact",
			value = "compact",
			icon = "📦",
			desc = "Floating windows",
		},
		{
			text = "Focus",
			value = "focus",
			icon = "🎯",
			desc = "Maximized conversation",
		},
	}

	Snacks.picker({
		source = "custom",
		title = " Select Layout ",
		items = layouts,
		format = function(item)
			local current = layout._state.current_preset
			local prefix = item.value == current and "● " or "  "
			return {
				text = {
					{ prefix, "SnacksPickerSpecial" },
					{ item.icon .. "  ", "SnacksPickerIcon" },
					{ item.text, "SnacksPickerItem" },
					{ "  " .. item.desc, "SnacksPickerComment" },
				},
			}
		end,
		confirm = function(picker, item)
			if item then
				ui.set_layout(item.value)
			end
		end,
		win = {
			input = {
				keys = {
					["<Tab>"] = {
						function(self)
							-- Preview layout on tab
							local item = self:current()
							if item then
								ui.set_layout(item.value)
							end
						end,
						desc = "Preview layout",
					},
				},
			},
		},
	})
end

-- Pick from recent conversations (placeholder for future)
function M.pick_conversation()
	notify.info("Conversation history coming soon!")
end

-- Pick from available MCP tools
function M.pick_tool()
	local Snacks = require("snacks")
	local tools = require("claude-code-ide.tools")

	local tool_list = {}
	for _, tool in ipairs(tools.list()) do
		table.insert(tool_list, {
			text = tool.name,
			value = tool.name,
			icon = "🔧",
			desc = tool.description,
			tool = tool,
		})
	end

	Snacks.picker({
		source = "custom",
		title = " Available MCP Tools ",
		items = tool_list,
		format = function(item)
			return {
				text = {
					{ item.icon .. "  ", "SnacksPickerIcon" },
					{ item.text, "SnacksPickerItem" },
					{ "  " .. item.desc, "SnacksPickerComment" },
				},
			}
		end,
		confirm = function(picker, item)
			if item then
				notify.info("Tool: " .. item.text .. "\n" .. vim.inspect(item.tool.inputSchema))
			end
		end,
	})
end

return M
