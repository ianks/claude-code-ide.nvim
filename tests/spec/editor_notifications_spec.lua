describe("claude-code-ide editor notifications", function()
	local notifications = require("claude-code-ide.editor_notifications")
	local temp_file = vim.fn.tempname() .. ".lua"
	
	before_each(function()
		-- Create a temporary file
		vim.fn.writefile({"-- Test file", "local x = 1"}, temp_file)
		-- Clear any existing autocmds
		pcall(vim.api.nvim_del_augroup_by_name, "ClaudeCodeNotifications")
		-- Mock send_notification to track calls
		notifications._sent = {}
		notifications.send_notification = function(method, params)
			table.insert(notifications._sent, {method = method, params = params})
		end
	end)
	
	after_each(function()
		-- Cleanup
		notifications.cleanup()
		pcall(vim.fn.delete, temp_file)
		-- Wipe all buffers
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_valid(buf) then
				pcall(vim.api.nvim_buf_delete, buf, {force = true})
			end
		end
	end)
	
	it("should only notify for real files", function()
		notifications.setup()
		
		-- Open a real file
		vim.cmd("edit " .. temp_file)
		vim.wait(150) -- Wait for debounce
		
		-- Should have sent notification
		assert.equals(1, #notifications._sent)
		assert.equals("selection_changed", notifications._sent[1].method)
		assert.equals(vim.fn.resolve(temp_file), notifications._sent[1].params.filePath)
		
		-- Clear sent notifications
		notifications._sent = {}
		
		-- Open a special buffer
		vim.cmd("enew")
		vim.bo.buftype = "nofile"
		vim.bo.filetype = "claude_conversation"
		vim.wait(150) -- Wait for debounce
		
		-- Should NOT have sent notification
		assert.equals(0, #notifications._sent)
	end)
	
	it("should debounce file change notifications", function()
		notifications.setup()
		
		-- Rapidly switch between files
		local temp_file2 = vim.fn.tempname() .. ".lua"
		vim.fn.writefile({"-- Test file 2"}, temp_file2)
		
		vim.cmd("edit " .. temp_file)
		vim.cmd("edit " .. temp_file2)
		vim.cmd("edit " .. temp_file)
		vim.cmd("edit " .. temp_file2)
		
		-- Wait for debounce
		vim.wait(150)
		
		-- Should only have one notification (last file)
		assert.equals(1, #notifications._sent)
		assert.equals(vim.fn.resolve(temp_file2), notifications._sent[1].params.filePath)
		
		vim.fn.delete(temp_file2)
	end)
	
	it("should debounce cursor movement notifications", function()
		notifications.setup()
		
		-- Open a real file
		vim.cmd("edit " .. temp_file)
		vim.wait(150) -- Wait for initial notification
		notifications._sent = {} -- Clear
		
		-- Move cursor multiple times rapidly
		vim.api.nvim_win_set_cursor(0, {1, 0})
		vim.cmd("doautocmd CursorMoved")
		vim.api.nvim_win_set_cursor(0, {1, 5})
		vim.cmd("doautocmd CursorMoved")
		vim.api.nvim_win_set_cursor(0, {2, 0})
		vim.cmd("doautocmd CursorMoved")
		vim.api.nvim_win_set_cursor(0, {2, 5})
		vim.cmd("doautocmd CursorMoved")
		
		-- Wait less than debounce time (debounce is 300ms)
		vim.wait(200)
		assert.equals(0, #notifications._sent)
		
		-- Wait for full debounce
		vim.wait(150)
		
		-- Should have exactly one notification
		assert.equals(1, #notifications._sent)
		assert.equals("selection_changed", notifications._sent[1].method)
	end)
	
	it("should skip non-file URIs", function()
		notifications.setup()
		
		-- Create buffers with various non-file URIs
		local test_cases = {
			"http://example.com",
			"https://github.com/test",
			"ftp://server.com/file",
			"term://bash",
			"fugitive://repo/.git//0/file.txt",
		}
		
		for _, uri in ipairs(test_cases) do
			vim.cmd("enew")
			vim.api.nvim_buf_set_name(0, uri)
			vim.wait(150) -- Wait for debounce
		end
		
		-- Should not have sent any notifications
		assert.equals(0, #notifications._sent)
	end)
end)