describe("claude-code-ide diff window logic", function()
	local diff = require("claude-code-ide.ui.diff")
	
	before_each(function()
		-- Clear any existing diff buffers
		diff.close_all_diffs()
		-- Close all windows except current
		vim.cmd("only")
	end)
	
	after_each(function()
		-- Clean up
		diff.close_all_diffs()
		vim.cmd("only")
	end)
	
	it("should open diff in current window if not a Claude window", function()
		-- Create a normal buffer in current window
		local normal_buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(normal_buf)
		vim.bo[normal_buf].filetype = "lua"
		
		local current_win = vim.api.nvim_get_current_win()
		
		-- Open a diff
		local result = diff.open_diff({
			old_file_path = "/tmp/test.lua",
			new_file_path = "/tmp/test.lua",
			new_file_contents = "-- Test content",
		})
		
		-- Should use the same window
		assert.equals(current_win, vim.api.nvim_get_current_win())
		assert.is_number(result.buffer)
	end)
	
	it("should find non-Claude window when current is Claude window", function()
		-- Create a Claude window
		local claude_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[claude_buf].filetype = "claude_conversation"
		vim.api.nvim_set_current_buf(claude_buf)
		
		-- Create a normal window split
		vim.cmd("vsplit")
		local normal_buf = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_set_current_buf(normal_buf)
		vim.bo[normal_buf].filetype = "lua"
		local normal_win = vim.api.nvim_get_current_win()
		
		-- Go back to Claude window
		vim.cmd("wincmd p")
		assert.equals("claude_conversation", vim.bo.filetype)
		
		-- Open a diff
		local result = diff.open_diff({
			old_file_path = "/tmp/test.lua",
			new_file_path = "/tmp/test.lua",
			new_file_contents = "-- Test content",
		})
		
		-- Should open in the normal window, not Claude window
		assert.equals(normal_win, vim.api.nvim_get_current_win())
	end)
	
	it("should create new split if only Claude windows exist", function()
		-- Create only Claude windows
		local claude_buf = vim.api.nvim_create_buf(false, true)
		vim.bo[claude_buf].filetype = "claude_conversation"
		vim.api.nvim_set_current_buf(claude_buf)
		
		local initial_win_count = #vim.api.nvim_list_wins()
		
		-- Open a diff
		local result = diff.open_diff({
			old_file_path = "/tmp/test.lua",
			new_file_path = "/tmp/test.lua",
			new_file_contents = "-- Test content",
		})
		
		-- Should create a new window
		assert.equals(initial_win_count + 1, #vim.api.nvim_list_wins())
		assert.is_number(result.buffer)
	end)
end)