-- Advanced configuration example for claude-code-ide.nvim
-- This showcases all available configuration options

return {
	"ianks/claude-code-ide.nvim",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"folke/snacks.nvim",
	},
	config = function()
		require("claude-code-ide").setup({
			-- Server Configuration
			server = {
				host = "127.0.0.1",
				port = 0, -- 0 = random port (recommended)
				lock_file_dir = vim.fn.expand("~/.claude/ide"),
				server_name = "claude-code-ide.nvim",
				server_version = "0.1.0",
			},

			-- UI Configuration
			ui = {
				-- Conversation window settings
				conversation = {
					position = "right", -- Options: left, right, top, bottom, float
					width = 50, -- Width for left/right positions (columns or percentage)
					height = 20, -- Height for top/bottom positions (lines or percentage)
					border = "rounded", -- Border style: none, single, double, rounded, solid, shadow
					wrap = true, -- Wrap long lines
					show_timestamps = true, -- Show message timestamps
					relative_timestamps = true, -- Show relative time (e.g., "5m ago")
					auto_scroll = true, -- Auto-scroll to bottom on new messages
					focus_on_open = true, -- Focus conversation window when opened
					theme = "auto", -- Theme: auto, light, dark
				},

				-- Progress indicators
				progress = {
					enabled = true,
					show_in_statusline = true,
					animation_style = "dots", -- Options: dots, bars, spinner, pulse
					animation_speed = 100, -- milliseconds between frames
					custom_stages = nil, -- Custom animation frames array
				},

				-- Layout system
				layout = {
					active = "default", -- Active layout preset
					presets = {
						default = {
							position = "right",
							width = 50,
						},
						coding = {
							position = "bottom",
							height = 15,
							wrap = false,
						},
						review = {
							position = "float",
							width = 0.8, -- 80% of editor width
							height = 0.8, -- 80% of editor height
						},
						minimal = {
							position = "right",
							width = 40,
							show_timestamps = false,
						},
					},
				},
			},

			-- Performance Settings
			performance = {
				-- Caching configuration
				cache = {
					enabled = true,
					ttl = 300, -- Default cache TTL in seconds
					max_size = 100, -- Maximum cache entries per cache type
					cleanup_interval = 300, -- Cleanup interval in seconds
				},

				-- Request queue configuration
				queue = {
					enabled = true,
					max_concurrent = 3, -- Max concurrent requests
					max_queued = 50, -- Max queued requests
					timeout = 30000, -- Request timeout in milliseconds
					retry_attempts = 3, -- Number of retry attempts
					retry_delay = 1000, -- Delay between retries in milliseconds
					rate_limit = 10, -- Requests per minute (0 = unlimited)
					priority_boost_recent = true, -- Boost priority of recent requests
				},
			},

			-- Code Execution (Experimental)
			code_execution = {
				enabled = false, -- Enable code execution feature
				terminal = "integrated", -- Options: integrated, external
				terminal_position = "bottom", -- Position for integrated terminal
				terminal_size = 15, -- Size of terminal window
				confirm_before_run = true, -- Ask before executing code
				save_before_run = true, -- Save file before executing
				auto_detect_language = true, -- Auto-detect language from filetype
				language_commands = {
					-- Custom commands for languages
					python = "python3",
					javascript = "node",
					lua = "lua",
					-- Add more as needed
				},
			},

			-- Keymaps Configuration
			keymaps = {
				-- Set to false to disable all default keymaps
				-- Set individual mappings to false to disable specific ones

				-- Global mappings
				toggle = "<leader>cc", -- Toggle conversation window
				send = "<leader>cs", -- Send selection/context
				send_visual = "<leader>cs", -- Send visual selection
				palette = "<leader>cp", -- Open command palette
				diagnostics = "<leader>cd", -- Send diagnostics
				retry = "<leader>cr", -- Retry last request
				clear = "<leader>cx", -- Clear conversation
				new_conversation = "<leader>cn", -- New conversation

				-- Conversation window mappings
				send_message = "<C-Enter>", -- Send message in insert mode
				close = "q", -- Close conversation window
				focus_input = "i", -- Focus input area
				scroll_up = "<C-u>", -- Scroll up
				scroll_down = "<C-d>", -- Scroll down
				copy_message = "yy", -- Copy message under cursor
				copy_last = "yl", -- Copy last Claude response

				-- Layout mappings
				next_pane = "<Tab>", -- Next pane in layout
				prev_pane = "<S-Tab>", -- Previous pane in layout
				zoom_toggle = "<leader>z", -- Toggle pane zoom

				-- Quick actions
				quick_fix = "<leader>qf", -- Quick fix at cursor
				quick_explain = "<leader>qe", -- Quick explain selection
				quick_review = "<leader>qr", -- Quick code review
				quick_test = "<leader>qt", -- Generate test for selection

				-- Terminal mappings (if code execution is enabled)
				execute_selection = "e", -- Execute selection
				execute_buffer = "E", -- Execute entire buffer
				open_terminal = "T", -- Open terminal
			},

			-- Autocmds Configuration
			autocmds = {
				-- Set to false to disable all autocmds
				-- Set individual autocmds to false to disable specific ones

				-- Auto-save conversation on buffer leave
				auto_save_conversation = true,

				-- Auto-resize conversation window
				auto_resize = true,

				-- Show diagnostics hint when errors exist
				diagnostic_hints = true,

				-- Update file resources on save
				update_resources_on_save = true,

				-- Highlight Claude's code blocks
				highlight_code_blocks = true,
			},

			-- Logging Configuration
			log = {
				level = "INFO", -- Options: TRACE, DEBUG, INFO, WARN, ERROR
				file = vim.fn.stdpath("data") .. "/claude-code-ide.log",
				max_size = 1048576, -- 1MB max log file size
				format = "[%timestamp%] [%level%] %module%: %message%",
			},

			-- Advanced Settings
			advanced = {
				-- MCP protocol version
				protocol_version = "2025-06-18",

				-- Custom SSL options (if needed)
				ssl = {
					verify = true,
					ca_bundle = nil, -- Path to custom CA bundle
				},

				-- Custom headers for WebSocket
				headers = {},

				-- Resource registration
				resources = {
					auto_register_files = true, -- Auto-register open files
					auto_register_workspace = true, -- Auto-register workspace info
					custom_templates_dir = nil, -- Path to custom templates
					custom_snippets_dir = nil, -- Path to custom snippets
				},

				-- Tool registration
				tools = {
					custom_tools_dir = nil, -- Path to custom tools
					enable_experimental = false, -- Enable experimental tools
				},
			},

			-- Debug settings
			debug = false, -- Enable debug mode
			debug_log_file = nil, -- Custom debug log file path
		})

		-- Start the server automatically
		vim.defer_fn(function()
			require("claude-code-ide").start()
		end, 100)
	end,
}
