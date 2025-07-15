-- claude-code.nvim plugin entry point
-- This file is loaded automatically by Neovim

if vim.g.loaded_claude_code then
	return
end
vim.g.loaded_claude_code = true

-- Check Neovim version
if vim.fn.has("nvim-0.8.0") == 0 then
	vim.api.nvim_err_writeln("claude-code.nvim requires Neovim 0.8.0 or later")
	return
end

-- Create user commands
vim.api.nvim_create_user_command("ClaudeCode", function(opts)
	local claude = require("claude-code")

	if opts.args == "start" then
		claude.setup()
	elseif opts.args == "stop" then
		claude.stop()
	elseif opts.args == "status" then
		local status = claude.status()
		vim.notify(vim.inspect(status), vim.log.levels.INFO)
	else
		vim.notify("Usage: :ClaudeCode [start|stop|status]", vim.log.levels.WARN)
	end
end, {
	nargs = 1,
	complete = function()
		return { "start", "stop", "status" }
	end,
	desc = "Control Claude Code server",
})

-- Auto-start if configured
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		if vim.g.claude_code_auto_start then
			vim.defer_fn(function()
				require("claude-code").setup()
			end, 100)
		end
	end,
	desc = "Auto-start Claude Code server",
})
