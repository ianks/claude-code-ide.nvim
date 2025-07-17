-- Configuration management for claude-code-ide.nvim
-- Provides a comprehensive settings system with validation and defaults

local M = {}
local notify = require("claude-code-ide.ui.notify")
local log = require("claude-code-ide.log")

-- Default configuration
local defaults = {
	-- Server configuration
	server = {
		enabled = true,
		host = "127.0.0.1",
		port = 0, -- 0 means random port
		port_range = { 10000, 65535 },
		auto_start = false, -- Don't auto-start server by default
		shutdown_on_exit = true,
	},

	-- Lock file settings
	lock_file = {
		path = vim.fn.expand("~/.claude/nvim/servers.lock"),
		permissions = "600",
	},

	-- UI configuration
	ui = {
		-- Conversation window
		conversation = {
			position = "right",
			width = 80,
			min_width = 60,
			max_width = 120,
			border = "rounded",
			wrap = true,
			show_help_footer = true,
			auto_focus = true,
		},

		-- Layout presets
		layout = {
			default_preset = "default",
			auto_resize = true,
			smart_layout = {
				enabled = true,
				breakpoints = {
					compact = 120,
					default = 180,
					full = 240,
				},
			},
		},

		-- Progress indicators
		progress = {
			enabled = true,
			animations = {
				default = "dots",
				ai_processing = "ai_thinking",
				code_analysis = "code_analysis",
			},
			show_timer = true,
			show_percentage = true,
		},

		-- Notifications
		notifications = {
			enabled = true,
			level = vim.log.levels.INFO,
			timeout = 3000,
			position = "top-right",
		},
	},

	-- Queue configuration
	queue = {
		max_concurrent = 3,
		max_queue_size = 100,
		timeout_ms = 30000,
		retry = {
			enabled = true,
			max_retries = 3,
			backoff_ms = 1000,
		},
		rate_limit = {
			enabled = true,
			max_requests = 30,
			window_ms = 60000,
			retry_after_ms = 5000,
		},
	},

	-- Keymaps configuration
	keymaps = {
		enabled = true,
		prefix = "<leader>c",
		mappings = {
			toggle = "c",
			send_selection = "s",
			send_file = "f",
			send_diagnostics = "d",
			open_diff = "D",
			new_conversation = "n",
			clear_conversation = "x",
			retry_last = "r",
			show_palette = "p",
			toggle_context = "t",
			toggle_preview = "v",
			cycle_layout = "l",
			-- Terminal integration
			execute_selection = "e",
			execute_buffer = "E",
			open_terminal = "T",
		},
	},

	-- Autocommands configuration
	autocmds = {
		enabled = true,
		auto_open_on_error = {
			enabled = false,
			severity = vim.diagnostic.severity.ERROR,
			debounce_ms = 500,
		},
		auto_follow_file = {
			enabled = true,
			pattern = "*",
		},
		smart_layout_resize = {
			enabled = true,
			debounce_ms = 100,
		},
	},

	-- Features configuration
	features = {
		-- Code execution
		code_execution = {
			enabled = false,
			terminal = "integrated", -- integrated, external
			terminal_position = "bottom", -- bottom, right, float
			terminal_size = 15, -- Height for bottom, width for right
			confirm_before_run = true,
			save_before_run = true,
		},

		-- Caching
		cache = {
			enabled = true,
			directory = vim.fn.stdpath("cache") .. "/claude-code",
			max_size_mb = 100,
			ttl_minutes = 60,
			persist_across_sessions = true,
		},

		-- Session management
		sessions = {
			auto_save = true,
			auto_restore = false,
			directory = vim.fn.stdpath("data") .. "/claude-code-ide/sessions",
			max_history = 100,
		},

		-- Diagnostics integration
		diagnostics = {
			enabled = true,
			include_hints = false,
			format = "detailed", -- simple, detailed
			group_by_file = true,
		},
	},

	-- Debug settings
	debug = {
		enabled = false,
		log_file = vim.fn.stdpath("state") .. "/claude-code-ide.log",
		log_level = "info",
		profile = false,
		experimental = {
			streaming_responses = false,
			multi_model_support = false,
		},
	},
}

-- Current configuration
local config = {}

-- Validation schemas
local schemas = {
	server = {
		port = { type = "number", min = 0, max = 65535 },
		host = { type = "string", pattern = "^[%d%.]+$" },
		enabled = { type = "boolean" },
		auto_start = { type = "boolean" },
		shutdown_on_exit = { type = "boolean" },
		port_range = { type = "table", array = true, length = 2 },
	},
	ui = {
		conversation = {
			position = { type = "string", enum = { "left", "right", "top", "bottom", "float", "center" } },
			width = { type = "number", min = 20, max = 300 },
			min_width = { type = "number", min = 20 },
			max_width = { type = "number", max = 300 },
			border = { type = "string", enum = { "none", "single", "double", "rounded", "solid", "shadow" } },
			wrap = { type = "boolean" },
			show_help_footer = { type = "boolean" },
			auto_focus = { type = "boolean" },
		},
		notifications = {
			enabled = { type = "boolean" },
			level = { type = "number" },
			timeout = { type = "number", min = 0 },
			position = { type = "string", enum = { "top-left", "top-right", "bottom-left", "bottom-right" } },
		},
	},
	queue = {
		max_concurrent = { type = "number", min = 1, max = 10 },
		max_queue_size = { type = "number", min = 10, max = 1000 },
		timeout_ms = { type = "number", min = 1000, max = 300000 },
	},
	keymaps = {
		enabled = { type = "boolean" },
		prefix = { type = "string" },
	},
}

-- Validate a value against a schema
local function validate_value(value, schema, path)
	if not schema then
		return true, nil
	end

	-- Check type
	if schema.type and type(value) ~= schema.type then
		return false, string.format("%s: expected %s, got %s", path, schema.type, type(value))
	end

	-- Check array
	if schema.array and not vim.tbl_islist(value) then
		return false, string.format("%s: expected array", path)
	end

	-- Check array length
	if schema.length and #value ~= schema.length then
		return false, string.format("%s: expected %d elements", path, schema.length)
	end

	-- Check enum
	if schema.enum then
		local valid = false
		for _, allowed in ipairs(schema.enum) do
			if value == allowed then
				valid = true
				break
			end
		end
		if not valid then
			return false, string.format("%s: must be one of %s", path, table.concat(schema.enum, ", "))
		end
	end

	-- Check numeric constraints
	if type(value) == "number" then
		if schema.min and value < schema.min then
			return false, string.format("%s: must be >= %d", path, schema.min)
		end
		if schema.max and value > schema.max then
			return false, string.format("%s: must be <= %d", path, schema.max)
		end
	end

	-- Check string pattern
	if type(value) == "string" and schema.pattern then
		if not value:match(schema.pattern) then
			return false, string.format("%s: invalid format", path)
		end
	end

	return true, nil
end

-- Validate configuration recursively
local function validate_config(cfg, schema, path)
	path = path or "config"
	local errors = {}

	-- Validate each field
	for key, value in pairs(cfg) do
		local field_path = path .. "." .. key
		local field_schema = schema and schema[key]

		if type(value) == "table" and not vim.tbl_islist(value) then
			-- Recurse into nested tables
			local nested_errors = validate_config(value, field_schema, field_path)
			vim.list_extend(errors, nested_errors)
		else
			-- Validate leaf value
			local ok, err = validate_value(value, field_schema, field_path)
			if not ok then
				table.insert(errors, err)
			end
		end
	end

	return errors
end

-- Merge user config with defaults
function M.setup(opts)
	opts = opts or {}
	config = vim.tbl_deep_extend("force", defaults, opts)

	-- Validate configuration
	local errors = validate_config(config, schemas)
	if #errors > 0 then
		for _, err in ipairs(errors) do
			notify.error("Configuration error: " .. err)
		end
		notify.error("Using default configuration due to errors")
		config = vim.deepcopy(defaults)
	end

	-- Ensure directories exist
	local lock_dir = vim.fn.fnamemodify(config.lock_file.path, ":h")
	vim.fn.mkdir(lock_dir, "p")

	if config.features.cache.enabled then
		vim.fn.mkdir(config.features.cache.directory, "p")
	end

	if config.features.sessions.auto_save or config.features.sessions.auto_restore then
		vim.fn.mkdir(config.features.sessions.directory, "p")
	end

	-- Apply configuration
	M.apply()

	-- Log configuration
	log.debug("CONFIG", "Configuration loaded", {
		server_enabled = config.server.enabled,
		ui_preset = config.ui.layout.default_preset,
		queue_concurrent = config.queue.max_concurrent,
		debug = config.debug.enabled,
	})

	return config
end

-- Apply configuration settings
function M.apply()
	-- Set log level
	if config.debug.log_level then
		log.set_level(config.debug.log_level)
	end

	-- Apply keymaps if enabled
	if config.keymaps.enabled then
		local keymaps = require("claude-code-ide.keymaps")
		if keymaps.setup then
			keymaps.setup(config.keymaps)
		end
	end

	-- Apply autocmds if enabled
	if config.autocmds.enabled then
		local autocmds = require("claude-code-ide.autocmds")
		if autocmds.setup then
			autocmds.setup(config.autocmds)
		end
	end
end

-- Get configuration value
function M.get(path)
	if not path then
		return config
	end

	local value = config
	for part in path:gmatch("[^%.]+") do
		if type(value) ~= "table" then
			return nil
		end
		value = value[part]
	end

	return value
end

-- Set configuration value
function M.set(path, value)
	local parts = {}
	for part in path:gmatch("[^%.]+") do
		table.insert(parts, part)
	end

	if #parts == 0 then
		return false
	end

	local current = config
	for i = 1, #parts - 1 do
		local part = parts[i]
		if type(current[part]) ~= "table" then
			current[part] = {}
		end
		current = current[part]
	end

	current[parts[#parts]] = value

	-- Re-apply configuration
	M.apply()

	return true
end

-- Reset configuration to defaults
function M.reset()
	config = vim.deepcopy(defaults)
	M.apply()
	notify.info("Configuration reset to defaults")
end

-- Save configuration to file
function M.save(filepath)
	filepath = filepath or vim.fn.stdpath("config") .. "/claude-code-config.json"

	local content = vim.json.encode(config)
	local file = io.open(filepath, "w")
	if not file then
		notify.error("Failed to save configuration to " .. filepath)
		return false
	end

	file:write(content)
	file:close()

	notify.success("Configuration saved to " .. filepath)
	return true
end

-- Load configuration from file
function M.load(filepath)
	filepath = filepath or vim.fn.stdpath("config") .. "/claude-code-config.json"

	local file = io.open(filepath, "r")
	if not file then
		return false
	end

	local content = file:read("*all")
	file:close()

	local ok, loaded = pcall(vim.json.decode, content)
	if not ok then
		notify.error("Failed to parse configuration file: " .. loaded)
		return false
	end

	-- Setup with loaded config
	M.setup(loaded)

	notify.success("Configuration loaded from " .. filepath)
	return true
end

-- Get default configuration
function M.get_defaults()
	return vim.deepcopy(defaults)
end

-- Validate user configuration (for testing)
function M.validate(user_config)
	local test_config = vim.tbl_deep_extend("force", defaults, user_config or {})
	local errors = validate_config(test_config, schemas)
	return #errors == 0, errors
end

-- Backward compatibility
function M._validate(cfg)
	-- Validate port range
	if cfg.server.port_range[1] > cfg.server.port_range[2] then
		error("Invalid port range: start must be less than end")
	end

	-- Validate UI position
	local valid_positions = { "left", "right", "top", "bottom", "float" }
	if not vim.tbl_contains(valid_positions, cfg.ui.conversation.position) then
		error("Invalid conversation position: " .. cfg.ui.conversation.position)
	end
end

-- Export for access
M.defaults = defaults
M.schemas = schemas

return M
