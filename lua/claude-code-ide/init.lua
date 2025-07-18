-- claude-code-ide.nvim
-- Simple terminal interface for Claude Code

local M = {}

-- State
M._state = {
	terminal = nil,
	server = nil,
	initialized = false,
}

-- Toggle Claude terminal
function M.toggle()
	if not M._state.initialized then
		vim.notify("Run :lua require('claude-code-ide').setup() first", vim.log.levels.WARN)
		return
	end
	
	local Snacks = require("snacks")
	
	-- If terminal exists and is visible, hide it
	if M._state.terminal and M._state.terminal.win and M._state.terminal.win:valid() then
		M._state.terminal:hide()
		return
	end
	
	-- Create or show terminal
	if not M._state.terminal then
		M._state.terminal = Snacks.terminal("claude --ide", {
			win = {
				position = "right",
				width = 0.4,
			},
		})
	else
		M._state.terminal:show()
	end
end

-- Setup
function M.setup(opts)
	opts = opts or {}
	
	-- Start MCP server
	local server = require("claude-code-ide.server")
	M._state.server = server.start({
		port = opts.port or 0,
		host = opts.host or "127.0.0.1",
		lock_file_dir = vim.fn.expand("~/.claude/ide"),
		server_name = "claude-code-ide.nvim",
		server_version = "0.1.0",
	})
	
	-- Setup keymap
	vim.keymap.set("n", "<leader>ct", M.toggle, {
		desc = "Toggle Claude terminal",
		silent = true,
	})
	
	M._state.initialized = true
end

return M