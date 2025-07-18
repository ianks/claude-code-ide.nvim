-- Interactive setup wizard for claude-code-ide.nvim
-- Guides new users through initial configuration

local M = {}
local notify = require("claude-code-ide.ui.notify")

-- Wizard steps
local steps = {
	{
		title = "Welcome to Claude Code IDE!",
		content = {
			"This wizard will help you set up Claude Code integration with Neovim.",
			"",
			"You'll need:",
			"• Claude CLI installed (we'll help with this)",
			"• An Anthropic API key (optional)",
			"",
			"Press <Enter> to continue or <Esc> to skip setup.",
		},
		action = function(state)
			return true -- Continue to next step
		end
	},
	{
		title = "Check Claude CLI Installation",
		content = function(state)
			-- Check if claude command exists
			local has_claude = vim.fn.executable("claude") == 1
			
			if has_claude then
				state.claude_installed = true
				return {
					"✓ Claude CLI is installed!",
					"",
					"Version: " .. vim.fn.system("claude --version"):gsub("\n", ""),
					"",
					"Press <Enter> to continue.",
				}
			else
				state.claude_installed = false
				return {
					"✗ Claude CLI not found.",
					"",
					"You need to install the Claude CLI to use this plugin.",
					"",
					"Options:",
					"1. Press <Enter> to open installation instructions",
					"2. Press <s> to skip (you can install later)",
					"3. Press <Esc> to exit wizard",
				}
			end
		end,
		action = function(state, choice)
			if not state.claude_installed and choice == "" then
				vim.ui.open("https://github.com/anthropics/claude-cli#installation")
				return false -- Stay on this step
			end
			return true
		end,
		keymaps = {
			s = function(state)
				state.skip_claude = true
				return true -- Continue to next step
			end
		}
	},
	{
		title = "Configure Auto-start",
		content = {
			"Claude Code can start automatically when you open Neovim.",
			"",
			"This reduces friction and ensures Claude is always ready.",
			"",
			"Would you like to enable auto-start? (Recommended)",
			"",
			"Press <y> for Yes (default)",
			"Press <n> for No",
		},
		action = function(state, choice)
			if choice == "n" then
				state.auto_start = false
			else
				state.auto_start = true
			end
			return true
		end,
		keymaps = {
			y = function(state)
				state.auto_start = true
				return true
			end,
			n = function(state)
				state.auto_start = false
				return true
			end
		}
	},
	{
		title = "Configure Keymaps",
		content = {
			"Claude Code uses <leader>c as the default prefix for commands.",
			"",
			"Common keymaps:",
			"• <leader>cc - Send selection to Claude",
			"• <leader>cf - Send function to Claude",
			"• <leader>co - Connect Claude CLI",
			"",
			"Would you like to use these default keymaps?",
			"",
			"Press <y> for Yes (default)",
			"Press <n> for No",
			"Press <c> to customize prefix",
		},
		action = function(state, choice)
			if choice == "n" then
				state.keymaps = false
			elseif choice == "c" then
				-- Custom prefix
				vim.ui.input({
					prompt = "Enter keymap prefix (e.g., <leader>ai): ",
					default = "<leader>c",
				}, function(input)
					if input and input ~= "" then
						state.keymap_prefix = input
					end
				end)
				return false -- Stay on this step to confirm
			else
				state.keymaps = true
			end
			return true
		end,
		keymaps = {
			y = function(state)
				state.keymaps = true
				return true
			end,
			n = function(state)
				state.keymaps = false
				return true
			end,
			c = function(state)
				return "c" -- Let action handle it
			end
		}
	},
	{
		title = "Configure Statusline",
		content = {
			"Claude Code can show connection status in your statusline.",
			"",
			"This helps you see when Claude is connected and working.",
			"",
			"Enable statusline integration?",
			"",
			"Press <y> for Yes (default)",
			"Press <n> for No",
		},
		action = function(state, choice)
			if choice == "n" then
				state.statusline = false
			else
				state.statusline = true
			end
			return true
		end,
		keymaps = {
			y = function(state)
				state.statusline = true
				return true
			end,
			n = function(state)
				state.statusline = false
				return true
			end
		}
	},
	{
		title = "Setup Complete!",
		content = function(state)
			local lines = {
				"Your Claude Code configuration is ready!",
				"",
				"Configuration summary:",
			}
			
			-- Add configuration details
			table.insert(lines, "• Auto-start: " .. (state.auto_start and "Enabled" or "Disabled"))
			table.insert(lines, "• Keymaps: " .. (state.keymaps and "Enabled" or "Disabled"))
			if state.keymap_prefix then
				table.insert(lines, "  Prefix: " .. state.keymap_prefix)
			end
			table.insert(lines, "• Statusline: " .. (state.statusline and "Enabled" or "Disabled"))
			
			table.insert(lines, "")
			table.insert(lines, "Next steps:")
			
			if not state.claude_installed then
				table.insert(lines, "1. Install Claude CLI")
			end
			
			table.insert(lines, (state.claude_installed and "1" or "2") .. ". Run :ClaudeCodeConnect to start")
			table.insert(lines, "")
			table.insert(lines, "Press <Enter> to apply configuration")
			
			return lines
		end,
		action = function(state)
			-- Generate configuration
			local config = {
				auto_start = state.auto_start,
				keymaps = state.keymaps and {} or false,
				statusline = state.statusline,
			}
			
			if state.keymap_prefix then
				config.keymaps = { prefix = state.keymap_prefix }
			end
			
			-- Apply configuration
			require("claude-code-ide").setup(config)
			
			-- Save configuration preference
			M.save_wizard_completion(config)
			
			notify.success("Claude Code setup complete!")
			
			-- Show helpful tip
			if state.auto_start then
				notify.info("Claude Code will start automatically next time you open Neovim")
			else
				notify.info("Run :ClaudeCode start to begin")
			end
			
			return true
		end
	}
}

-- Save that wizard was completed
function M.save_wizard_completion(config)
	local data_dir = vim.fn.stdpath("data") .. "/claude-code-ide"
	vim.fn.mkdir(data_dir, "p")
	
	local wizard_file = data_dir .. "/wizard_completed.json"
	local file = io.open(wizard_file, "w")
	if file then
		file:write(vim.json.encode({
			completed = true,
			timestamp = os.time(),
			config = config
		}))
		file:close()
	end
end

-- Check if wizard was completed
function M.was_completed()
	local wizard_file = vim.fn.stdpath("data") .. "/claude-code-ide/wizard_completed.json"
	return vim.fn.filereadable(wizard_file) == 1
end

-- Run the setup wizard
function M.run()
	local state = {}
	local current_step = 1
	
	local function show_step()
		local step = steps[current_step]
		if not step then
			return -- Wizard complete
		end
		
		-- Build content
		local content = step.content
		if type(content) == "function" then
			content = content(state)
		end
		
		-- Create buffer
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].filetype = "markdown"
		
		-- Add content
		local lines = {
			"# " .. step.title,
			"",
		}
		vim.list_extend(lines, content)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.bo[buf].modifiable = false
		
		-- Create window
		local ok, snacks = pcall(require, "Snacks")
		local win
		
		if ok and snacks.win then
			win = snacks.win({
				buf = buf,
				title = " Claude Code Setup Wizard ",
				border = "rounded",
				width = 60,
				height = 20,
				row = 0.5,
				col = 0.5,
			})
		else
			-- Fallback to native window
			local width = 60
			local height = 20
			local row = math.floor((vim.o.lines - height) / 2)
			local col = math.floor((vim.o.columns - width) / 2)
			
			win = vim.api.nvim_open_win(buf, true, {
				relative = "editor",
				width = width,
				height = height,
				row = row,
				col = col,
				border = "rounded",
				title = " Claude Code Setup Wizard ",
				title_pos = "center",
			})
		end
		
		-- Set up keymaps
		local function close_window()
			if win and type(win) == "table" and win.close then
				win:close()
			elseif win and type(win) == "number" and vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end
		
		-- Default keymaps
		vim.keymap.set("n", "<Esc>", function()
			close_window()
			notify.info("Setup wizard cancelled")
		end, { buffer = buf })
		
		vim.keymap.set("n", "<Enter>", function()
			local continue = true
			if step.action then
				continue = step.action(state, "")
			end
			
			if continue then
				current_step = current_step + 1
				close_window()
				vim.defer_fn(show_step, 50)
			end
		end, { buffer = buf })
		
		-- Step-specific keymaps
		if step.keymaps then
			for key, handler in pairs(step.keymaps) do
				vim.keymap.set("n", key, function()
					local result = handler(state)
					if result == true then
						current_step = current_step + 1
						close_window()
						vim.defer_fn(show_step, 50)
					elseif type(result) == "string" then
						-- Pass result to action
						if step.action then
							local continue = step.action(state, result)
							if continue then
								current_step = current_step + 1
								close_window()
								vim.defer_fn(show_step, 50)
							end
						end
					end
				end, { buffer = buf })
			end
		end
	end
	
	-- Start wizard
	show_step()
end

-- Check and run wizard if needed
function M.check_and_run()
	if not M.was_completed() then
		vim.defer_fn(function()
			notify.info("Welcome! Starting setup wizard...")
			M.run()
		end, 1000)
		return true
	end
	return false
end

return M