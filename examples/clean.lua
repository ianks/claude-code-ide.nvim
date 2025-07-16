-- Clean configuration for claude-code.nvim
-- No auto-open windows, no notifications, just the essentials

return {
	"ianks/claude-code.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"folke/snacks.nvim", -- For the best UI experience
	},
	config = function()
		require("claude-code").setup({
			-- All defaults, no customization needed
		})

		-- Optionally start the server automatically (silent)
		-- vim.defer_fn(function()
		--   require("claude-code").start()
		-- end, 100)
	end,
	keys = {
		{ "<leader>cc", "<cmd>ClaudeCodeToggle<cr>", desc = "Toggle Claude conversation" },
		{ "<leader>cs", "<cmd>ClaudeCodeSend<cr>", mode = { "n", "v" }, desc = "Send to Claude" },
		{ "<leader>cd", "<cmd>ClaudeCodeDiagnostics<cr>", desc = "Send diagnostics to Claude" },
		{ "<leader>cp", "<cmd>ClaudeCodePalette<cr>", desc = "Claude command palette" },
	},
}
