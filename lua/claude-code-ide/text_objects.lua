-- Text objects for claude-code-ide.nvim
-- Provides intelligent code selection for sending to Claude

local M = {}
local ts_utils = require("nvim-treesitter.ts_utils")

-- Get the current function node
local function get_function_node()
	local node = ts_utils.get_node_at_cursor()
	if not node then return nil end
	
	-- Walk up the tree to find a function node
	while node do
		local type = node:type()
		-- Support multiple languages
		if type == "function_declaration" or
		   type == "function_definition" or
		   type == "function" or
		   type == "method_declaration" or
		   type == "method_definition" or
		   type == "method" or
		   type == "arrow_function" or
		   type == "function_expression" or
		   type == "lambda_expression" or
		   type == "anonymous_function" then
			return node
		end
		node = node:parent()
	end
	
	return nil
end

-- Get the current class node
local function get_class_node()
	local node = ts_utils.get_node_at_cursor()
	if not node then return nil end
	
	-- Walk up the tree to find a class node
	while node do
		local type = node:type()
		-- Support multiple languages
		if type == "class_declaration" or
		   type == "class_definition" or
		   type == "class" or
		   type == "struct_declaration" or
		   type == "struct_definition" or
		   type == "interface_declaration" or
		   type == "interface_definition" or
		   type == "impl_item" then
			return node
		end
		node = node:parent()
	end
	
	return nil
end

-- Get the current code block (statement block)
local function get_block_node()
	local node = ts_utils.get_node_at_cursor()
	if not node then return nil end
	
	-- Walk up the tree to find a block node
	while node do
		local type = node:type()
		if type == "block" or
		   type == "statement_block" or
		   type == "compound_statement" or
		   type == "do_statement" or
		   type == "while_statement" or
		   type == "for_statement" or
		   type == "if_statement" then
			return node
		end
		node = node:parent()
	end
	
	return nil
end

-- Get node text with proper range
local function get_node_text(node, bufnr)
	if not node then return "" end
	
	local start_row, start_col, end_row, end_col = node:range()
	local lines = vim.api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
	
	if #lines == 0 then return "" end
	
	-- Handle single line
	if #lines == 1 then
		lines[1] = string.sub(lines[1], start_col + 1, end_col)
	else
		-- Handle multi-line
		lines[1] = string.sub(lines[1], start_col + 1)
		lines[#lines] = string.sub(lines[#lines], 1, end_col)
	end
	
	return table.concat(lines, "\n")
end

-- Get current function text
function M.get_function_text()
	local node = get_function_node()
	if not node then
		return nil, "No function found at cursor position"
	end
	
	local bufnr = vim.api.nvim_get_current_buf()
	local text = get_node_text(node, bufnr)
	
	return text, nil
end

-- Get current class text
function M.get_class_text()
	local node = get_class_node()
	if not node then
		return nil, "No class found at cursor position"
	end
	
	local bufnr = vim.api.nvim_get_current_buf()
	local text = get_node_text(node, bufnr)
	
	return text, nil
end

-- Get current block text
function M.get_block_text()
	local node = get_block_node()
	if not node then
		return nil, "No code block found at cursor position"
	end
	
	local bufnr = vim.api.nvim_get_current_buf()
	local text = get_node_text(node, bufnr)
	
	return text, nil
end

-- Get current paragraph (non-treesitter based)
function M.get_paragraph_text()
	-- Save cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	
	-- Use vim's paragraph text object
	vim.cmd("normal! vip")
	
	-- Get selection
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	
	-- Exit visual mode
	vim.cmd("normal! ")
	
	-- Restore cursor
	vim.api.nvim_win_set_cursor(0, cursor)
	
	-- Get lines
	local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
	
	if #lines == 0 then
		return nil, "No paragraph at cursor position"
	end
	
	return table.concat(lines, "\n"), nil
end

-- Get visual selection text
function M.get_visual_selection()
	-- Get visual selection range
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	
	local start_line = start_pos[2]
	local start_col = start_pos[3]
	local end_line = end_pos[2]
	local end_col = end_pos[3]
	
	-- Get lines
	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	
	if #lines == 0 then
		return nil, "No selection"
	end
	
	-- Handle visual mode column adjustment
	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" then
		-- Adjust for inclusive selection
		if #lines == 1 then
			lines[1] = string.sub(lines[1], start_col, end_col)
		else
			lines[1] = string.sub(lines[1], start_col)
			lines[#lines] = string.sub(lines[#lines], 1, end_col)
		end
	end
	
	return table.concat(lines, "\n"), nil
end

-- Send text to Claude
local function send_to_claude(text, context)
	if not text or text == "" then
		require("claude-code-ide.ui.notify").warn("No text to send")
		return
	end
	
	-- TODO: Integrate with Claude conversation API
	local conversation = require("claude-code-ide.ui.conversation")
	
	-- Add context prefix
	local message = text
	if context then
		message = string.format("```%s\n%s\n```", context, text)
	end
	
	-- Append to conversation
	conversation.append("user", message)
	
	-- Show conversation window if not visible
	conversation.show()
	
	require("claude-code-ide.ui.notify").info("Sent " .. (context or "text") .. " to Claude")
end

-- Send current function to Claude
function M.send_function()
	local text, err = M.get_function_text()
	if err then
		require("claude-code-ide.ui.notify").warn(err)
		return
	end
	
	local filetype = vim.bo.filetype
	send_to_claude(text, filetype .. " function")
end

-- Send current class to Claude
function M.send_class()
	local text, err = M.get_class_text()
	if err then
		require("claude-code-ide.ui.notify").warn(err)
		return
	end
	
	local filetype = vim.bo.filetype
	send_to_claude(text, filetype .. " class")
end

-- Send current block to Claude
function M.send_block()
	local text, err = M.get_block_text()
	if err then
		require("claude-code-ide.ui.notify").warn(err)
		return
	end
	
	local filetype = vim.bo.filetype
	send_to_claude(text, filetype .. " block")
end

-- Send current paragraph to Claude
function M.send_paragraph()
	local text, err = M.get_paragraph_text()
	if err then
		require("claude-code-ide.ui.notify").warn(err)
		return
	end
	
	send_to_claude(text, "paragraph")
end

-- Send visual selection to Claude
function M.send_selection()
	local text, err = M.get_visual_selection()
	if err then
		-- If no visual selection, try current line
		text = vim.api.nvim_get_current_line()
		if text == "" then
			require("claude-code-ide.ui.notify").warn("No text to send")
			return
		end
	end
	
	local filetype = vim.bo.filetype
	send_to_claude(text, filetype)
end

-- Send entire buffer to Claude
function M.send_buffer()
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local text = table.concat(lines, "\n")
	
	if text == "" then
		require("claude-code-ide.ui.notify").warn("Buffer is empty")
		return
	end
	
	local filename = vim.fn.expand("%:t")
	local filetype = vim.bo.filetype
	send_to_claude(text, filetype .. " file: " .. filename)
end

-- Setup keymaps
function M.setup_keymaps()
	-- Visual mode: send selection
	vim.keymap.set("v", "<leader>cc", function()
		M.send_selection()
	end, { desc = "Send selection to Claude" })
	
	-- Normal mode mappings
	vim.keymap.set("n", "<leader>cc", function()
		M.send_selection()
	end, { desc = "Send current line to Claude" })
	
	vim.keymap.set("n", "<leader>cf", function()
		M.send_function()
	end, { desc = "Send current function to Claude" })
	
	vim.keymap.set("n", "<leader>cC", function()
		M.send_class()
	end, { desc = "Send current class to Claude" })
	
	vim.keymap.set("n", "<leader>cp", function()
		M.send_paragraph()
	end, { desc = "Send current paragraph to Claude" })
	
	vim.keymap.set("n", "<leader>cb", function()
		M.send_buffer()
	end, { desc = "Send entire buffer to Claude" })
	
	vim.keymap.set("n", "<leader>cB", function()
		M.send_block()
	end, { desc = "Send current block to Claude" })
end

return M