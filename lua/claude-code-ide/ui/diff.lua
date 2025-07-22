-- Diff preview UI for claude-code-ide.nvim
-- Shows unified diff in a non-blocking preview split

local M = {}

-- State tracking for diff tabs
local diff_tabs = {}

-- Create a diff preview window using Snacks
---@param opts table Options for diff preview
---@field old_file_path string Path to original file
---@field new_file_path string Path to new file
---@field new_file_contents string Contents of the new file
---@field on_accept? function Callback when changes are accepted
---@field on_reject? function Callback when changes are rejected
---@return table diff_window The created window
function M.show(opts)
	local Snacks = require("snacks")

	-- Read the original file content
	local orig_file_path = vim.fn.expand(opts.old_file_path)
	local orig_lines = {}
	if vim.fn.filereadable(orig_file_path) == 1 then
		orig_lines = vim.fn.readfile(orig_file_path)
	end

	-- Split new content into lines
	local new_lines = vim.split(opts.new_file_contents, "\n", { plain = true })

	-- Create a unified diff using vim's diff functionality
	-- Write temporary files for diffing
	local orig_tmp = vim.fn.tempname()
	local new_tmp = vim.fn.tempname()
	vim.fn.writefile(orig_lines, orig_tmp)
	vim.fn.writefile(new_lines, new_tmp)

	-- Get the diff
	local diff_cmd = string.format("diff -u %s %s", vim.fn.shellescape(orig_tmp), vim.fn.shellescape(new_tmp))
	local diff_output = vim.fn.systemlist and vim.fn.systemlist(diff_cmd) or {}

	-- Clean up temp files
	vim.fn.delete(orig_tmp)
	vim.fn.delete(new_tmp)

	-- Format the diff output
	local diff_lines = {}
	if diff_output and #diff_output > 0 then
		-- Replace temp file names with actual file names in the diff header
		for i, line in ipairs(diff_output) do
			if i == 1 and line:match("^%-%-%-") then
				table.insert(diff_lines, "--- " .. opts.old_file_path)
			elseif i == 2 and line:match("^%+%+%+") then
				table.insert(diff_lines, "+++ " .. opts.new_file_path .. " (Claude's changes)")
			else
				table.insert(diff_lines, line)
			end
		end
	else
		-- Create a simple diff view when diff command is not available
		table.insert(diff_lines, "--- " .. opts.old_file_path)
		table.insert(diff_lines, "+++ " .. opts.new_file_path .. " (Claude's changes)")
		table.insert(diff_lines, "@@ Changes @@")

		-- Show the new content with + prefix
		for _, line in ipairs(new_lines) do
			table.insert(diff_lines, "+ " .. line)
		end
	end

	-- Create a buffer for the diff
	local diff_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_lines)
	vim.bo[diff_buf].filetype = "diff"
	vim.bo[diff_buf].buftype = "nofile"
	vim.bo[diff_buf].modifiable = false

	-- Track whether we've already made a decision
	local decision_made = false

	-- Function to handle accept
	local function accept_changes()
		if decision_made then
			return
		end
		decision_made = true
		if opts.on_accept then
			opts.on_accept(new_lines)
		end
	end

	-- Function to handle reject
	local function reject_changes()
		if decision_made then
			return
		end
		decision_made = true
		if opts.on_reject then
			opts.on_reject()
		end
	end

	-- Create a non-blocking preview split instead of modal window
	local diff_win = Snacks.win({
		buf = diff_buf,
		position = "right",
		width = 0.5,
		height = 1.0,
		border = "single",
		title = string.format(" Diff Preview: %s ", vim.fn.fnamemodify(opts.old_file_path, ":t")),
		title_pos = "center",
		footer = " <Enter> Accept | <Esc>/q Reject | <Tab> Toggle view ",
		footer_pos = "center",
		focusable = true,
		zindex = 10, -- Lower z-index to not block other windows
		keys = {
			["<Enter>"] = function()
				accept_changes()
				return "close"
			end,
			["<Esc>"] = function()
				reject_changes()
				return "close"
			end,
			q = function()
				reject_changes()
				return "close"
			end,
			-- Allow normal navigation to switch focus
			["<C-w>h"] = function()
				vim.cmd("wincmd h")
			end,
			["<C-w>l"] = function()
				vim.cmd("wincmd l")
			end,
			["<C-w>j"] = function()
				vim.cmd("wincmd j")
			end,
			["<C-w>k"] = function()
				vim.cmd("wincmd k")
			end,
			["<Tab>"] = function()
				-- Toggle between unified diff and side-by-side view
				local current_ft = vim.bo[diff_buf].filetype
				if current_ft == "diff" then
					-- Show side-by-side comparison
					vim.bo[diff_buf].modifiable = true
					vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, {})

					-- Add a simple side-by-side view
					local max_len = 0
					for _, line in ipairs(orig_lines) do
						max_len = math.max(max_len, #line)
					end

					local compare_lines = {
						"ORIGINAL" .. string.rep(" ", max_len - 8 + 3) .. "│ CLAUDE'S CHANGES",
						string.rep("─", max_len + 2) .. "┼" .. string.rep("─", max_len + 2),
					}

					local max_lines = math.max(#orig_lines, #new_lines)
					for i = 1, max_lines do
						local orig_line = orig_lines[i] or ""
						local new_line = new_lines[i] or ""
						local padding = string.rep(" ", max_len - #orig_line + 2)
						table.insert(compare_lines, orig_line .. padding .. "│ " .. new_line)
					end

					vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, compare_lines)
					vim.bo[diff_buf].filetype = "text"
					vim.bo[diff_buf].modifiable = false
				else
					-- Switch back to unified diff
					vim.bo[diff_buf].modifiable = true
					vim.api.nvim_buf_set_lines(diff_buf, 0, -1, false, diff_lines)
					vim.bo[diff_buf].filetype = "diff"
					vim.bo[diff_buf].modifiable = false
				end
			end,
		},
		on_close = function()
			-- Don't auto-reject on close if user is just switching windows
			-- Only reject if explicitly closed with q or Esc
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(diff_buf) then
					vim.api.nvim_buf_delete(diff_buf, { force = true })
				end
			end)
		end,
		wo = {
			cursorline = true,
			number = false,
			relativenumber = false,
			signcolumn = "no",
			foldcolumn = "0",
			spell = false,
			list = false,
			wrap = false,
		},
	})

	-- Return the window for potential manipulation
	return {
		win = diff_win,
		close = function()
			if diff_win:valid() then
				diff_win:close()
			end
		end,
	}
end

-- Open diff (alias for show with tab tracking)
---@param opts table Options for diff preview
---@return table result Status of diff operation
function M.open_diff(opts)
	local tab_name = opts.tab_name or ("Diff: " .. vim.fn.fnamemodify(opts.new_file_path or opts.old_file_path, ":t"))

	-- Create a new tab for the diff
	vim.cmd("tabnew")
	local tab_id = vim.api.nvim_get_current_tabpage()

	-- Store the tab info for later cleanup
	diff_tabs[tab_id] = {
		name = tab_name,
		old_file_path = opts.old_file_path,
		new_file_path = opts.new_file_path,
	}

	-- Create the diff using the show method
	local diff_win = M.show(opts)

	-- Set tab name if provided
	if tab_name then
		vim.api.nvim_tabpage_set_var(tab_id, "tab_name", tab_name)
	end

	return {
		success = true,
		message = "Diff shown for " .. (opts.new_file_path or opts.old_file_path),
		tab_id = tab_id,
	}
end

-- Close all diff tabs
---@return number count Number of diff tabs closed
function M.close_all_diffs()
	local closed_count = 0
	local tabs_to_close = {}

	-- Collect all diff tabs
	for tab_id, _ in pairs(diff_tabs) do
		if vim.api.nvim_tabpage_is_valid(tab_id) then
			table.insert(tabs_to_close, tab_id)
		end
	end

	-- Close the tabs
	for _, tab_id in ipairs(tabs_to_close) do
		if vim.api.nvim_tabpage_is_valid(tab_id) then
			vim.api.nvim_set_current_tabpage(tab_id)
			vim.cmd("tabclose")
			closed_count = closed_count + 1
		end
		diff_tabs[tab_id] = nil
	end

	return closed_count
end

-- Close specific diff tab by name
---@param tab_name string Name of the tab to close
---@return boolean success Whether the tab was found and closed
function M.close_diff_tab(tab_name)
	for tab_id, tab_info in pairs(diff_tabs) do
		if tab_info.name == tab_name and vim.api.nvim_tabpage_is_valid(tab_id) then
			vim.api.nvim_set_current_tabpage(tab_id)
			vim.cmd("tabclose")
			diff_tabs[tab_id] = nil
			return true
		end
	end
	return false
end

return M
