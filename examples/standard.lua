-- Standard configuration for claude-code.nvim
-- This is the recommended "green path" setup that works out of the box

return {
	"ianks/claude-code.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"folke/snacks.nvim", -- For the best UI experience
	},
	config = function()
		-- Initialize with default settings
		require("claude-code").setup()

		-- That's it! The plugin is now ready to use.
		--
		-- Quick start:
		-- 1. Run :lua require("claude-code").start() to start the server
		-- 2. In another terminal, run: claude --ide
		-- 3. Press <leader>cc to open the Claude conversation window
		--
		-- Default keybindings:
		-- <leader>cc - Toggle Claude conversation
		-- <leader>cs - Send selection to Claude
		-- <leader>cd - Send diagnostics to Claude
		-- <leader>cp - Open command palette
	end,
}
