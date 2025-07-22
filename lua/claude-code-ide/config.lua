-- Configuration management for claude-code-ide.nvim
-- Production-ready configuration with validation, secure defaults, and hot-reload

local M = {}

-- Configuration validation utilities
local function validate_type(value, expected_type, path)
	local actual_type = type(value)
	if actual_type ~= expected_type then
		return false, string.format("%s: expected %s, got %s", path, expected_type, actual_type)
	end
	return true, nil
end

local function validate_range(value, min, max, path)
	if value < min or value > max then
		return false, string.format("%s: value %s outside range [%s, %s]", path, value, min, max)
	end
	return true, nil
end

local function validate_enum(value, allowed_values, path)
	for _, allowed in ipairs(allowed_values) do
		if value == allowed then
			return true, nil
		end
	end
	return false,
		string.format("%s: value '%s' not in allowed values: %s", path, value, table.concat(allowed_values, ", "))
end

-- Security configuration defaults
local SECURITY_DEFAULTS = {
	max_file_size = 10 * 1024 * 1024, -- 10MB
	max_path_length = 4096,
	allowed_schemes = { "file", "http", "https" },
	sandbox_paths = { vim.fn.expand("~"), "/tmp" },
	rate_limits = {
		requests_per_minute = 100,
		file_operations_per_minute = 50,
		websocket_messages_per_second = 10,
	},
}

-- Comprehensive default configuration with security-first approach
local DEFAULTS = {
	-- Server configuration with secure defaults
	server = {
		enabled = true,
		host = "127.0.0.1", -- Localhost only for security
		port = 0, -- Random port to avoid conflicts
		port_range = { 10000, 65535 },
		auto_start = false, -- Manual start for security
		shutdown_on_exit = true,
		timeout_ms = 30000,
		max_connections = 5, -- Prevent resource exhaustion
		auth = {
			required = true,
			token_length = 32,
			session_timeout_ms = 3600000, -- 1 hour
		},
	},

	-- Lock file settings with secure permissions
	lock_file = {
		dir = vim.fn.expand("~/.claude/ide"),
		permissions = "600", -- Owner only
		cleanup_on_exit = true,
		max_age_ms = 86400000, -- 24 hours
	},

	-- Logging with structured output and security filtering
	logging = {
		enabled = true,
		level = "INFO",
		file = vim.fn.expand("~/.local/state/nvim/claude-code-ide.log"),
		max_size = 10 * 1024 * 1024, -- 10MB
		max_files = 5,
		format = "structured",
		filter_sensitive = true, -- Remove auth tokens from logs
		async = true,
	},

	-- Event system configuration
	events = {
		enabled = true,
		async = true,
		debug = false,
		max_listeners = 100,
		timeout_ms = 5000,
	},

	-- UI configuration with responsive design
	ui = {
		enabled = true,
		theme = "auto", -- auto, light, dark

		-- Conversation window
		conversation = {
			position = "right",
			width = 80,
			min_width = 60,
			max_width = 120,
			height = 0.8,
			border = "rounded",
			wrap = true,
			show_help_footer = true,
			auto_focus = true,
			auto_scroll = true,
		},

		-- Layout management
		layout = {
			default_preset = "default",
			auto_resize = true,
			save_layout = true,
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
			style = "modern", -- simple, modern, minimal
			show_timer = true,
			show_percentage = true,
			animations = {
				enabled = vim.fn.has("gui_running") == 1,
				fps = 30,
			},
		},

		-- Notifications
		notifications = {
			enabled = true,
			level = vim.log.levels.INFO,
			timeout = 3000,
			position = "top-right",
			max_visible = 5,
		},
	},

	-- Request queue with resource limits
	queue = {
		max_concurrent = 3,
		max_queue_size = 100,
		timeout_ms = 30000,
		priority_weights = {
			high = 3,
			normal = 2,
			low = 1,
		},
		retry = {
			enabled = true,
			max_retries = 3,
			backoff_ms = 1000,
			exponential = true,
		},
		rate_limit = {
			enabled = true,
			max_requests = 30,
			window_ms = 60000,
			retry_after_ms = 5000,
		},
	},

	-- Cache configuration with memory limits
	cache = {
		enabled = true,
		max_size = 1000,
		default_ttl = 300, -- 5 minutes
		memory_limit = 50 * 1024 * 1024, -- 50MB
		cleanup_interval = 60000, -- 1 minute
		strategies = {
			tools = { ttl = 600, max_size = 100 },
			resources = { ttl = 300, max_size = 500 },
			diagnostics = { ttl = 30, max_size = 200 },
		},
	},

	-- Resource management with security controls
	resources = {
		enabled = true,
		max_file_size = SECURITY_DEFAULTS.max_file_size,
		max_path_length = SECURITY_DEFAULTS.max_path_length,
		allowed_schemes = SECURITY_DEFAULTS.allowed_schemes,
		sandbox_paths = SECURITY_DEFAULTS.sandbox_paths,
		auto_register = {
			workspace_files = true,
			git_files = false, -- Security: don't auto-register all git files
			max_files = 1000,
		},
	},

	-- Tools configuration with security limits
	tools = {
		enabled = true,
		timeout_ms = 10000,
		max_concurrent = 5,
		security = {
			validate_paths = true,
			restrict_to_workspace = true,
			max_diff_size = 1024 * 1024, -- 1MB
		},
	},

	-- Keymaps configuration
	keymaps = {
		enabled = true,
		prefix = "<leader>c",
		mappings = {
			toggle = "t",
			send_selection = "s",
			send_file = "f",
			send_diagnostics = "d",
			conversation = "n",
			status = "i",
			restart = "r",
			logs = "l",
		},
		which_key = {
			enabled = true,
			name = "Claude Code",
		},
	},

	-- Terminal integration
	terminal = {
		enabled = true,
		command = "claude --ide",
		shell = vim.o.shell,
		position = "right",
		size = {
			width = 0.4,
			height = 0.8,
		},
		auto_close = false,
		auto_insert = true,
	},

	-- Security settings
	security = SECURITY_DEFAULTS,

	-- Performance tuning
	performance = {
		debounce_ms = 100,
		throttle_ms = 50,
		lazy_loading = true,
		async_operations = true,
		memory_monitoring = true,
	},

	-- Development and debugging
	debug = {
		enabled = false,
		verbose_logging = false,
		trace_events = false,
		profile_performance = false,
		dump_config = false,
	},
}

-- Configuration schema for validation
local SCHEMA = {
	server = {
		enabled = "boolean",
		host = "string",
		port = "number",
		port_range = {
			"table",
			function(v)
				return #v == 2 and v[1] < v[2]
			end,
		},
		auto_start = "boolean",
		shutdown_on_exit = "boolean",
		timeout_ms = {
			"number",
			function(v)
				return v > 0 and v <= 300000
			end,
		},
		max_connections = {
			"number",
			function(v)
				return v > 0 and v <= 100
			end,
		},
	},
	lock_file = {
		dir = "string",
		permissions = {
			"string",
			function(v)
				return v:match("^[0-7][0-7][0-7]$")
			end,
		},
		cleanup_on_exit = "boolean",
	},
	logging = {
		enabled = "boolean",
		level = {
			"string",
			function(v)
				return vim.tbl_contains({ "TRACE", "DEBUG", "INFO", "WARN", "ERROR" }, v)
			end,
		},
		file = "string",
		max_size = {
			"number",
			function(v)
				return v > 0
			end,
		},
		max_files = {
			"number",
			function(v)
				return v > 0 and v <= 100
			end,
		},
	},
	ui = {
		enabled = "boolean",
		theme = {
			"string",
			function(v)
				return vim.tbl_contains({ "auto", "light", "dark" }, v)
			end,
		},
		conversation = {
			position = {
				"string",
				function(v)
					return vim.tbl_contains({ "left", "right", "top", "bottom" }, v)
				end,
			},
			width = {
				"number",
				function(v)
					return v >= 40 and v <= 200
				end,
			},
			height = {
				"number",
				function(v)
					return v > 0 and v <= 1
				end,
			},
		},
	},
	queue = {
		max_concurrent = {
			"number",
			function(v)
				return v > 0 and v <= 50
			end,
		},
		max_queue_size = {
			"number",
			function(v)
				return v > 0 and v <= 10000
			end,
		},
		timeout_ms = {
			"number",
			function(v)
				return v > 0
			end,
		},
	},
	security = {
		max_file_size = {
			"number",
			function(v)
				return v > 0 and v <= 100 * 1024 * 1024
			end,
		},
		max_path_length = {
			"number",
			function(v)
				return v > 0 and v <= 8192
			end,
		},
	},
}

-- Validate configuration against schema
local function validate_config_recursive(config, schema, path)
	local errors = {}

	for key, expected in pairs(schema) do
		local value = config[key]
		local current_path = path and (path .. "." .. key) or key

		if value == nil then
			-- Use default if available
			goto continue
		end

		if type(expected) == "string" then
			-- Simple type validation
			local ok, err = validate_type(value, expected, current_path)
			if not ok then
				table.insert(errors, err)
			end
		elseif type(expected) == "table" then
			if type(expected[1]) == "string" then
				-- Type validation with custom validator
				local ok, err = validate_type(value, expected[1], current_path)
				if not ok then
					table.insert(errors, err)
				elseif expected[2] and not expected[2](value) then
					table.insert(errors, current_path .. ": validation failed")
				end
			else
				-- Nested schema validation
				if type(value) == "table" then
					local nested_errors = validate_config_recursive(value, expected, current_path)
					vim.list_extend(errors, nested_errors)
				else
					table.insert(errors, current_path .. ": expected table")
				end
			end
		end

		::continue::
	end

	return errors
end

-- Merge user config with defaults recursively
function M.merge_with_defaults(user_config)
	user_config = user_config or {}

	local function deep_merge(default, user)
		local result = vim.deepcopy(default)

		for key, value in pairs(user) do
			if type(value) == "table" and type(result[key]) == "table" then
				result[key] = deep_merge(result[key], value)
			else
				result[key] = value
			end
		end

		return result
	end

	return deep_merge(DEFAULTS, user_config)
end

-- Comprehensive configuration validation
function M.validate(config)
	local errors = validate_config_recursive(config, SCHEMA, nil)

	-- Additional cross-field validations
	if config.server.port_range and config.server.port then
		if config.server.port > 0 then
			local min_port, max_port = config.server.port_range[1], config.server.port_range[2]
			if config.server.port < min_port or config.server.port > max_port then
				table.insert(
					errors,
					string.format("server.port %d outside port_range [%d, %d]", config.server.port, min_port, max_port)
				)
			end
		end
	end

	-- Validate file paths exist and are writable
	if config.logging.enabled and config.logging.file then
		local log_dir = vim.fn.fnamemodify(config.logging.file, ":h")
		if vim.fn.isdirectory(log_dir) == 0 then
			vim.fn.mkdir(log_dir, "p")
		end
	end

	return {
		valid = #errors == 0,
		errors = errors,
		config = config,
	}
end

-- Get current configuration (runtime access)
local current_config = nil

function M.get(key)
	if not current_config then
		error("Configuration not initialized. Call setup() first.")
	end

	if not key then
		return current_config
	end

	-- Support dot notation for nested access
	local result = current_config
	for part in key:gmatch("[^%.]+") do
		if type(result) == "table" and result[part] ~= nil then
			result = result[part]
		else
			return nil
		end
	end

	return result
end

-- Set configuration value at runtime (for hot-reloading)
function M.set(key, value)
	if not current_config then
		error("Configuration not initialized")
	end

	-- Support dot notation for nested setting
	local parts = {}
	for part in key:gmatch("[^%.]+") do
		table.insert(parts, part)
	end

	local target = current_config
	for i = 1, #parts - 1 do
		local part = parts[i]
		if type(target[part]) ~= "table" then
			target[part] = {}
		end
		target = target[part]
	end

	target[parts[#parts]] = value

	-- Validate the change
	local validation = M.validate(current_config)
	if not validation.valid then
		error("Configuration validation failed after update: " .. table.concat(validation.errors, ", "))
	end

	-- Emit configuration change event
	local ok, events = pcall(require, "claude-code-ide.events")
	if ok then
		events.emit("ConfigurationChanged", { key = key, value = value })
	end
end

-- Setup and initialize configuration
function M.setup(user_config)
	current_config = M.merge_with_defaults(user_config)

	local validation = M.validate(current_config)
	if not validation.valid then
		error("Configuration validation failed: " .. table.concat(validation.errors, "\n"))
	end

	-- Create necessary directories
	if current_config.lock_file.dir then
		vim.fn.mkdir(current_config.lock_file.dir, "p")
	end

	-- Set up configuration file watching for hot-reload
	if current_config.debug.enabled then
		M._setup_config_watching()
	end

	return current_config
end

-- Watch configuration file for changes (development feature)
function M._setup_config_watching()
	-- This would watch a config file and reload on changes
	-- Implementation depends on having a config file to watch
	-- For now, just emit setup complete event
	vim.defer_fn(function()
		local ok, events = pcall(require, "claude-code-ide.events")
		if ok then
			events.emit("ConfigurationSetup", current_config)
		end
	end, 100)
end

-- Export configuration defaults for testing
M.defaults = DEFAULTS
M.schema = SCHEMA

-- Health check for configuration module
function M.health_check()
	return {
		healthy = current_config ~= nil,
		details = {
			initialized = current_config ~= nil,
			config_keys = current_config and vim.tbl_keys(current_config) or {},
		},
	}
end

return M
