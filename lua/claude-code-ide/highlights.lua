-- Highlight definitions for claude-code-ide.nvim
-- Provides distinctive visual styling for Claude UI components

local M = {}

-- Default highlight groups
M.defaults = {
	-- Conversation window highlights
	ClaudeConversationNormal = { link = "Normal", bg = "#1a1b26" }, -- Slightly darker background
	ClaudeConversationFloat = { link = "NormalFloat" },
	ClaudeConversationBorder = { fg = "#7aa2f7", bg = "#1a1b26" }, -- Blue border matching Claude branding
	ClaudeConversationCursorLine = { bg = "#292e42" },
	ClaudeConversationSignColumn = { bg = "#1a1b26" },
	
	-- Status line highlights
	ClaudeStatusLine = { fg = "#7aa2f7", bg = "#24283b", bold = true },
	ClaudeStatusLineNC = { fg = "#565f89", bg = "#1a1b26" },
	
	-- Title and footer
	ClaudeTitle = { fg = "#7aa2f7", bg = "#24283b", bold = true },
	ClaudeFooter = { fg = "#565f89", bg = "#1a1b26", italic = true },
	
	-- Message role highlights
	ClaudeUserMessage = { fg = "#9ece6a", bold = true },
	ClaudeAssistantMessage = { fg = "#7aa2f7", bold = true },
	ClaudeSystemMessage = { fg = "#565f89", italic = true },
	
	-- Progress and notifications
	ClaudeProgress = { fg = "#7aa2f7", bold = true },
	ClaudeSuccess = { fg = "#9ece6a", bold = true },
	ClaudeError = { fg = "#f7768e", bold = true },
	ClaudeWarning = { fg = "#e0af68", bold = true },
	
	-- Interactive elements
	ClaudeButton = { fg = "#1a1b26", bg = "#7aa2f7", bold = true },
	ClaudeButtonHover = { fg = "#1a1b26", bg = "#89b4fa", bold = true },
	ClaudeLink = { fg = "#7dcfff", underline = true },
	
	-- Code blocks and selections
	ClaudeCodeBlock = { bg = "#24283b" },
	ClaudeSelection = { bg = "#3b4261" },
}

-- Setup highlight groups
function M.setup()
	for name, attrs in pairs(M.defaults) do
		vim.api.nvim_set_hl(0, name, attrs)
	end
	
	-- Set up autocommand to reapply highlights on colorscheme change
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("ClaudeHighlights", { clear = true }),
		callback = function()
			M.setup()
		end,
	})
end

-- Get highlight attributes for a group
function M.get(name)
	return M.defaults[name] or {}
end

-- Update a highlight group
function M.set(name, attrs)
	M.defaults[name] = attrs
	vim.api.nvim_set_hl(0, name, attrs)
end

-- Link a Claude highlight to another group
function M.link(claude_group, target_group)
	M.defaults[claude_group] = { link = target_group }
	vim.api.nvim_set_hl(0, claude_group, { link = target_group })
end

return M