-- claude-code-ide.nvim plugin entry point
-- This file is loaded automatically by Neovim

if vim.g.loaded_claude_code then
	return
end
vim.g.loaded_claude_code = true

-- Check Neovim version
if vim.fn.has("nvim-0.8.0") == 0 then
	vim.api.nvim_err_writeln("claude-code-ide.nvim requires Neovim 0.8.0 or later")
	return
end

-- Create user commands
vim.api.nvim_create_user_command("ClaudeCode", function(opts)
	local claude = require("claude-code-ide")

	if opts.args == "start" then
		claude.start()
	elseif opts.args == "stop" then
		claude.stop()
	elseif opts.args == "status" then
		local status = claude.status()
		local notify = require("claude-code-ide.ui.notify")
		notify.info(vim.inspect(status), { title = "Claude Code Status" })
	else
		local notify = require("claude-code-ide.ui.notify")
		notify.warn("Usage: :ClaudeCode [start|stop|status]")
	end
end, {
	nargs = 1,
	complete = function()
		return { "start", "stop", "status" }
	end,
	desc = "Control Claude Code server",
})

-- Create ClaudeCodeConnect command to launch Claude CLI
vim.api.nvim_create_user_command("ClaudeCodeConnect", function(opts)
	local claude = require("claude-code-ide")
	local status = claude.status()
	local notify = require("claude-code-ide.ui.notify")
	
	if not status.initialized or not status.server_running then
		notify.warn("Claude Code server is not running. Starting server...")
		claude.start()
		vim.defer_fn(function()
			-- Give server time to start and create lock file
			local job = require("plenary.job")
			job:new({
				command = "claude",
				args = { "code" },
				on_exit = function(j, return_val)
					if return_val ~= 0 then
						notify.error_with_action(
							"Failed to launch Claude CLI. Make sure 'claude' command is installed.",
							"<leader>ci",
							"install Claude CLI",
							function()
								vim.ui.open("https://github.com/anthropics/claude-cli#installation")
							end
						)
					end
				end,
			}):start()
		end, 500)
	else
		-- Server already running, just launch Claude CLI
		local job = require("plenary.job")
		job:new({
			command = "claude",
			args = { "code" },
			on_exit = function(j, return_val)
				if return_val ~= 0 then
					notify.error_with_action(
						"Failed to launch Claude CLI. Make sure 'claude' command is installed.",
						"<leader>ci",
						"install Claude CLI",
						function()
							vim.ui.open("https://github.com/anthropics/claude-cli#installation")
						end
					)
				end
			end,
		}):start()
	end
end, {
	desc = "Launch Claude CLI and connect to Neovim",
})

-- Note: auto-start is now handled in setup() function based on config.auto_start
