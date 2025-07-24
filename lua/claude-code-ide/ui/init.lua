-- UI components for claude-code-ide.nvim
-- Modern UI using snacks.nvim for a buttery smooth experience

local M = {}
local events = require("claude-code-ide.events")
local layout = require("claude-code-ide.ui.layout")

-- State management
local state = {
	conversation = nil, ---@type snacks.win?
	context = nil, ---@type snacks.win?
	preview = nil, ---@type snacks.win?
	progress = nil, ---@type table? Progress instance
	conversation_history = {}, ---@type table[]
	current_request = nil, ---@type table?
	layout_preset = "default", ---@type string
}

-- UI configuration with modern defaults
local default_config = {
	conversation = {
		style = "claude_conversation",
		position = "right",
		width = 90,
		min_width = 70,
		max_width = 120,
		border = "double",
		title = " ✳️ Claude Code • AI Assistant ",
		title_pos = "center",
		footer = " [q]uit [?]help [<C-s>]end [<C-p>]alette [<C-w>] window ",
		footer_pos = "center",
		backdrop = false,
		enter = true,
		fixbuf = true,
		minimal = false,
		ft = "markdown",
		zindex = 100,
		wo = {
			wrap = true,
			linebreak = true,
			conceallevel = 2,
			concealcursor = "nc",
			spell = false,
			foldenable = false,
			foldcolumn = "0",
			winfixwidth = true,
			winhighlight = "Normal:ClaudeConversationNormal,NormalFloat:ClaudeConversationFloat,FloatBorder:ClaudeConversationBorder,CursorLine:ClaudeConversationCursorLine,SignColumn:ClaudeConversationSignColumn",
			statusline = "%#ClaudeStatusLine# ✳️ Claude Code %=%#ClaudeStatusLineNC# %{&modified?'[+]':''} ",
			signcolumn = "no",
			number = false,
			relativenumber = false,
		},
		bo = {
			filetype = "claude_conversation",
			buftype = "nofile",
			bufhidden = "hide",
			modifiable = false,
			swapfile = false,
			undofile = false,
		},
		keys = {
			q = function(self)
				local confirm = vim.fn.confirm("Close Claude Code Assistant?", "&Yes\n&No", 2)
				if confirm == 1 then
					self:close()
				end
			end,
			["<C-c>"] = function(self)
				local confirm = vim.fn.confirm("Close Claude Code Assistant?", "&Yes\n&No", 2)
				if confirm == 1 then
					self:close()
				end
			end,
			["?"] = function(self)
				self:toggle_help({
					win = { position = "float", width = 60, height = 20 },
				})
			end,
			["<C-s>"] = function(_self)
				M.send_current()
			end,
			["<C-r>"] = function(_self)
				M.retry_last()
			end,
			["<C-n>"] = function(_self)
				M.new_conversation()
			end,
			["<C-d>"] = function(_self)
				M.clear_conversation()
			end,
			["<C-p>"] = function(_self)
				M.show_command_palette()
			end,
		},
		on_close = function(_self)
			state.conversation = nil
			events.emit(events.events.UI_CONVERSATION_CLOSED, {})
		end,
	},
	progress_style = {
		icon = " ",
		title = "Claude Processing",
		timeout = false,
	},
	notifications = {
		enabled = true,
		timeout = 3000,
		icons = {
			error = " ",
			warn = " ",
			info = " ",
			debug = " ",
			trace = " ",
			success = " ",
		},
	},
}

-- Initialize conversation buffer with welcome content
local function init_conversation_buffer(buf)
	local lines = {
		"# ✳️ Claude Code",
		"",
		"Welcome to Claude Code - your AI programming assistant!",
		"",
		"## 🚀 Quick Start",
		"",
		"- **Send Selection**: Select text and press `<leader>cs`",
		"- **Send Current File**: Press `<leader>cc` in normal mode",
		"- **Send Diagnostics**: Press `<leader>cd` to send LSP diagnostics",
		"- **Open Diff**: Press `<leader>cD` to view suggested changes",
		"",
		"## ⌨️ Conversation Commands",
		"",
		"- `<C-s>` - Send current buffer/selection",
		"- `<C-r>` - Retry last request",
		"- `<C-n>` - Start new conversation",
		"- `<C-d>` - Clear conversation",
		"- `?` - Toggle this help",
		"- `q` - Close window",
		"",
		"## 📊 Status",
		"",
	}

	-- Add server status
	local server = require("claude-code-ide.server").get_server()
	if server and server.running then
		table.insert(lines, string.format("- **Server**: Running on port %d ✅", server.port))
		table.insert(lines, string.format("- **Clients**: %d connected", vim.tbl_count(server.clients)))
	else
		table.insert(lines, "- **Server**: Not running ❌")
		table.insert(lines, "- Run `:ClaudeCode start` to begin")
	end

	table.insert(lines, "")
	table.insert(lines, "---")
	table.insert(lines, "")
	table.insert(lines, "*Ready for your first question!*")

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
end

-- Get merged configuration
local function get_config()
	local claude = require("claude-code-ide")
	local user_config = claude.status().config or {}
	return vim.tbl_deep_extend("force", default_config, user_config.ui or {})
end

-- Toggle conversation window
function M.toggle_conversation()
	layout.toggle_pane("conversation")
	state.conversation = layout._state.windows.conversation
end

-- Open conversation window with modern UI
function M.open_conversation()
	-- Use layout system to open conversation
	local win = layout.open_pane("conversation", {
		on_buf = function(self)
			if vim.api.nvim_buf_line_count(self.buf) == 1 then
				init_conversation_buffer(self.buf)
			end
		end,
		keys = vim.tbl_extend("force", get_config().conversation.keys or {}, {
			["<C-l>"] = function()
				layout.cycle_layout()
			end,
			["<C-x>"] = function()
				M.toggle_context()
			end,
			["<C-p>"] = function()
				M.toggle_preview()
			end,
		}),
	})

	state.conversation = win
	return win
end

-- Close conversation window
function M.close_conversation()
	layout.close_pane("conversation")
	state.conversation = nil
end

-- Toggle context pane
function M.toggle_context()
	layout.toggle_pane("context")
	state.context = layout._state.windows.context

	-- Update context if opened
	if state.context and state.context:valid() then
		M.update_context()
	end
end

-- Toggle preview pane
function M.toggle_preview()
	layout.toggle_pane("preview")
	state.preview = layout._state.windows.preview
end

-- Update context pane with relevant information
function M.update_context()
	if not state.context or not state.context:valid() then
		return
	end

	local buf = state.context.buf
	local lines = {
		"## Current Context",
		"",
		"### File",
		vim.fn.expand("%:p"),
		"",
		"### Language",
		vim.bo.filetype,
		"",
		"### Diagnostics",
		string.format("%d total", #vim.diagnostic.get()),
		"",
		"### Open Buffers",
		string.format("%d files", #vim.tbl_filter(function(b)
			return vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) ~= ""
		end, vim.api.nvim_list_bufs())),
	}

	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
end

-- Show preview of suggested changes
---@param content string The content to preview
---@param filetype? string Optional filetype for syntax highlighting
function M.show_preview(content, filetype)
	if not state.preview then
		layout.open_pane("preview")
		state.preview = layout._state.windows.preview
	end

	if state.preview and state.preview:valid() then
		local buf = state.preview.buf
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(content, "\n"))
		vim.bo[buf].modifiable = false

		if filetype then
			vim.bo[buf].filetype = filetype
		end
	end
end

-- Apply a layout preset
---@param preset_name? string Name of the preset (default, split, full, compact, focus)
function M.set_layout(preset_name)
	preset_name = preset_name or "default"
	layout.apply_preset(preset_name)
	state.layout_preset = preset_name

	-- Restore windows if they were open
	if state.conversation then
		M.open_conversation()
	end
end

-- Get current layout info
function M.get_layout_info()
	return layout.get_info()
end

-- Add message to conversation
---@param role "user"|"assistant"|"system"
---@param content string
---@param metadata? table
function M.add_message(role, content, metadata)
	if not state.conversation or not state.conversation:valid() then
		M.open_conversation()
	end

	-- Create message entry
	local timestamp = os.date("%H:%M")
	local message = {
		role = role,
		content = content,
		timestamp = timestamp,
		metadata = metadata or {},
	}

	-- Add to history
	table.insert(state.conversation_history, message)

	-- Format message for display
	local lines = {}
	local separator = role == "user" and "###" or "---"

	if role == "user" then
		table.insert(lines, "")
		table.insert(lines, separator .. " User [" .. timestamp .. "] " .. separator)
		table.insert(lines, "")
	elseif role == "assistant" then
		table.insert(lines, "")
		table.insert(lines, separator .. " Claude [" .. timestamp .. "] " .. separator)
		table.insert(lines, "")
	else
		table.insert(lines, "")
		table.insert(lines, "*" .. content .. "*")
		table.insert(lines, "")
		return
	end

	-- Add content lines
	for line in content:gmatch("[^\n]+") do
		table.insert(lines, line)
	end

	-- Append to buffer
	local buf = state.conversation.buf
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
	vim.bo[buf].modifiable = false

	-- Scroll to bottom
	vim.schedule(function()
		if state.conversation and state.conversation:win_valid() then
			local win = state.conversation.win
			local line_count = vim.api.nvim_buf_line_count(buf)
			vim.api.nvim_win_set_cursor(win, { line_count, 0 })
		end
	end)
end

-- Show progress indicator
---@param message string
---@param opts? table
function M.show_progress(message, opts)
	local progress = require("claude-code-ide.ui.progress")

	-- Hide existing progress if any
	if state.progress then
		state.progress:stop()
	end

	-- Create new progress with AI animation by default
	opts = opts or {}
	opts.animation = opts.animation or "ai_processing"
	opts.style = opts.style or { title = "Claude Processing" }

	state.progress = progress.show(message, opts)
	return state.progress
end

-- Hide progress indicator
function M.hide_progress()
	if state.progress then
		state.progress:stop()
		state.progress = nil
	end
end

-- Send selection to Claude
---@param start_line number
---@param end_line number
function M.send_selection(start_line, end_line)
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	local text = table.concat(lines, "\n")
	local filename = vim.fn.expand("%:p")
	local filetype = vim.bo.filetype

	-- Build context
	local context = string.format(
		"File: %s\nLanguage: %s\nSelection (lines %d-%d):\n\n```%s\n%s\n```",
		filename,
		filetype,
		start_line,
		end_line,
		filetype,
		text
	)

	-- Add to conversation
	M.add_message("user", context)

	-- Show progress with code analysis animation
	local progress = require("claude-code-ide.ui.progress")
	state.progress = progress.code_analysis("Analyzing your code...")

	-- Store request for retry
	state.current_request = {
		type = "selection",
		data = { start_line = start_line, end_line = end_line },
	}

	-- TODO: Actually send to Claude via MCP
	vim.defer_fn(function()
		if state.progress then
			state.progress:complete("Code analyzed successfully!", true)
			state.progress = nil
		end
		M.add_message("assistant", "I received your code selection. How can I help you with it?")
	end, 2000)
end

-- Send current file/buffer
function M.send_current()
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		-- Visual mode - send selection
		local start_pos = vim.fn.getpos("'<")
		local end_pos = vim.fn.getpos("'>")
		M.send_selection(start_pos[2], end_pos[2])
	else
		-- Normal mode - send entire file
		local line_count = vim.api.nvim_buf_line_count(0)
		M.send_selection(1, line_count)
	end
end

-- Show diagnostics in conversation
function M.show_diagnostics()
	local diagnostics = vim.diagnostic.get()

	if #diagnostics == 0 then
		local Snacks = require("snacks")
		Snacks.notify("No diagnostics found", "info", {
			title = "Claude Code",
			icon = "✓",
		})
		return
	end

	-- Format diagnostics
	local grouped = {}
	for _, diag in ipairs(diagnostics) do
		local bufnr = diag.bufnr
		local filename = vim.api.nvim_buf_get_name(bufnr)
		grouped[filename] = grouped[filename] or {}
		table.insert(grouped[filename], diag)
	end

	-- Build diagnostic message
	local lines = { "## Diagnostics Report", "" }
	local total = 0

	for filename, diags in pairs(grouped) do
		table.insert(lines, "### " .. filename)
		table.insert(lines, "")

		for _, diag in ipairs(diags) do
			local severity = vim.diagnostic.severity[diag.severity]
			local icon = severity == "ERROR" and "❌" or severity == "WARN" and "⚠️ " or "ℹ️ "
			table.insert(
				lines,
				string.format("- %s **Line %d**: %s", icon, diag.lnum + 1, diag.message:gsub("\n", " "))
			)
			total = total + 1
		end
		table.insert(lines, "")
	end

	table.insert(lines, string.format("**Total**: %d diagnostic%s", total, total == 1 and "" or "s"))

	-- Add to conversation
	local content = table.concat(lines, "\n")
	M.add_message("user", content)

	-- Store request for retry
	state.current_request = {
		type = "diagnostics",
		data = {},
	}

	-- Show progress with AI thinking animation
	local progress = require("claude-code-ide.ui.progress")
	state.progress = progress.ai_thinking("Analyzing diagnostics...")

	-- TODO: Send to Claude
	vim.defer_fn(function()
		if state.progress then
			state.progress:complete("Analysis complete!", true)
			state.progress = nil
		end
		M.add_message("assistant", "I see you have " .. total .. " diagnostics. Let me help you fix these issues...")
	end, 1500)
end

-- Retry last request
function M.retry_last()
	if not state.current_request then
		local Snacks = require("snacks")
		Snacks.notify("No previous request to retry", "warn", {
			title = "Claude Code",
		})
		return
	end

	local req = state.current_request
	if req.type == "selection" then
		M.send_selection(req.data.start_line, req.data.end_line)
	elseif req.type == "diagnostics" then
		M.show_diagnostics()
	end
end

-- Clear conversation
function M.clear_conversation()
	if state.conversation and state.conversation:valid() then
		local buf = state.conversation.buf
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, {})
		init_conversation_buffer(buf)
		vim.bo[buf].modifiable = false
		state.conversation_history = {}
		state.current_request = nil

		local Snacks = require("snacks")
		Snacks.notify("Conversation cleared", "info", {
			title = "Claude Code",
			icon = "🗑️",
		})
	end
end

-- Start new conversation
function M.new_conversation()
	M.clear_conversation()
	M.add_message("system", "Started new conversation")
end

-- Show command palette
function M.show_command_palette()
	require("claude-code-ide.ui.picker").show_commands()
end

-- Export all functions
M.state = state -- Expose state for testing

return M
