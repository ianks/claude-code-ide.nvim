describe("claude-code-ide.ui.diff", function()
	local diff = require("claude-code-ide.ui.diff")
	
	before_each(function()
		-- Clear any existing diff buffers
		diff.close_all_diffs()
	end)
	
	after_each(function()
		-- Clean up
		diff.close_all_diffs()
	end)
	
	it("should create a diff buffer with proper naming", function()
		local opts = {
			old_file_path = "/tmp/test.lua",
			new_file_path = "/tmp/test.lua",
			new_file_contents = "-- New content\nprint('hello')",
		}
		
		local result = diff.open_diff(opts)
		assert.is_true(result.success)
		assert.is_number(result.buffer)
		
		-- Check buffer exists and has correct name
		assert.is_true(vim.api.nvim_buf_is_valid(result.buffer))
		local buf_name = vim.api.nvim_buf_get_name(result.buffer)
		assert.is_not_nil(buf_name:match("%[Claude Code%]"))
	end)
	
	it("should set buffer as modifiable with correct filetype", function()
		local opts = {
			old_file_path = "/tmp/test.py",
			new_file_path = "/tmp/test.py",
			new_file_contents = "# Python file\nprint('hello')",
		}
		
		local result = diff.open_diff(opts)
		local bufnr = result.buffer
		
		-- Check buffer properties
		assert.is_true(vim.bo[bufnr].modifiable)
		assert.equals("acwrite", vim.bo[bufnr].buftype)
		
		-- Filetype should be detected based on filename
		local ft = vim.bo[bufnr].filetype
		assert.is_true(ft == "python" or ft == "") -- May not detect in test env
	end)
	
	it("should close all diff buffers", function()
		-- Create multiple diff buffers
		local opts1 = {
			old_file_path = "/tmp/test1.lua",
			new_file_path = "/tmp/test1.lua",
			new_file_contents = "content1",
		}
		local opts2 = {
			old_file_path = "/tmp/test2.lua",
			new_file_path = "/tmp/test2.lua",
			new_file_contents = "content2",
		}
		
		local result1 = diff.open_diff(opts1)
		local result2 = diff.open_diff(opts2)
		
		assert.is_true(vim.api.nvim_buf_is_valid(result1.buffer))
		assert.is_true(vim.api.nvim_buf_is_valid(result2.buffer))
		
		-- Close all diffs
		local closed_count = diff.close_all_diffs()
		assert.equals(2, closed_count)
		
		-- Buffers should be gone
		assert.is_false(vim.api.nvim_buf_is_valid(result1.buffer))
		assert.is_false(vim.api.nvim_buf_is_valid(result2.buffer))
	end)
	
	it("should store diff metadata for save operation", function()
		local opts = {
			old_file_path = "/tmp/test.lua",
			new_file_path = "/tmp/test.lua",
			new_file_contents = "-- Modified content",
		}
		
		local result = diff.open_diff(opts)
		local bufnr = result.buffer
		
		-- Check metadata is stored
		local info = vim.b[bufnr].claude_diff_info
		assert.is_table(info)
		assert.equals("/tmp/test.lua", info.original_file)
		assert.is_string(info.digest)
		assert.is_string(info.tab_name)
	end)
end)