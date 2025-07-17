-- Example configuration for using the Claude Code file follower
-- This shows how to integrate automatic file following into your Neovim setup

-- Add this to your claude-code-ide.nvim configuration
require("claude-code-ide").setup({
	-- ... your existing configuration ...
})

-- Setup the file follower
local file_follower = require("examples.basic.file-follower")
file_follower.setup({
	follow_delay = 100, -- Delay in milliseconds before following
})

-- Optionally enable by default
file_follower.enable()

-- Key mappings for file follower control
vim.keymap.set("n", "<leader>cf", ":ClaudeFollowToggle<CR>", { desc = "Toggle Claude file following" })
vim.keymap.set("n", "<leader>cF", ":ClaudeFollowStatus<CR>", { desc = "Show Claude file follower status" })

-- Visual indicator in statusline
-- Add this to your statusline configuration
local function claude_follow_status()
	local ok, follower = pcall(require, "examples.basic.file-follower")
	if ok and follower and follower.is_enabled and follower.is_enabled() then
		return "󰄀" -- Eye icon when following is enabled
	end
	return ""
end

-- Example with lualine
-- lualine.setup({
--   sections = {
--     lualine_x = {
--       { claude_follow_status, color = { fg = '#50fa7b' } }
--     }
--   }
-- })

-- Auto-enable file following when Claude server starts
vim.api.nvim_create_autocmd("User", {
	pattern = "ClaudeCode:ServerStarted",
	callback = function()
		file_follower.enable()
		vim.notify("Auto-enabled Claude file following", vim.log.levels.INFO)
	end,
	desc = "Auto-enable file following when Claude server starts",
})

-- Auto-disable when server stops
vim.api.nvim_create_autocmd("User", {
	pattern = "ClaudeCode:ServerStopped",
	callback = function()
		file_follower.disable()
	end,
	desc = "Auto-disable file following when Claude server stops",
})
