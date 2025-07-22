-- claude-code-ide.nvim
-- Production-ready Claude Code integration with fail-safe architecture

local M = {}

-- Module dependencies with graceful fallbacks
local deps = {}
local function load_dependency(name, required)
	local ok, module = pcall(require, name)
	if ok then
		deps[name] = module
		return module
	elseif required then
		error(string.format("Critical dependency missing: %s", name))
	else
		vim.notify(string.format("Optional dependency unavailable: %s", name), vim.log.levels.WARN)
		return nil
	end
end

-- Preload critical dependencies
load_dependency("claude-code-ide.config", true)
load_dependency("claude-code-ide.events", true)
load_dependency("claude-code-ide.log", true)

-- Optional dependencies with fallbacks
local snacks = load_dependency("snacks", false)

-- Configuration constants
local CONFIG = {
	MIN_VIM_VERSION = { 0, 11, 0 },
	REQUIRED_FEATURES = { "autocmd", "timers" },
	STATE_CLEANUP_INTERVAL_MS = 30000,
}

-- Plugin state with comprehensive lifecycle management
local State = {
	initialized = false,
	server = nil,
	terminal = nil,
	timers = {},
	config = nil,
	cleanup_callbacks = {},
}

-- Validate Neovim environment
local function validate_environment()
	local errors = {}

	-- Check Neovim version
	local version = vim.version()
	if vim.version.lt(version, CONFIG.MIN_VIM_VERSION) then
		table.insert(
			errors,
			string.format(
				"Neovim %d.%d.%d+ required, found %d.%d.%d",
				CONFIG.MIN_VIM_VERSION[1],
				CONFIG.MIN_VIM_VERSION[2],
				CONFIG.MIN_VIM_VERSION[3],
				version.major,
				version.minor,
				version.patch
			)
		)
	end

	-- Check required features
	for _, feature in ipairs(CONFIG.REQUIRED_FEATURES) do
		if vim.fn.has(feature) == 0 then
			table.insert(errors, string.format("Required feature missing: %s", feature))
		end
	end

	if #errors > 0 then
		error("Environment validation failed:\n" .. table.concat(errors, "\n"))
	end

	return true
end

-- Register cleanup callback
local function register_cleanup(callback)
	table.insert(State.cleanup_callbacks, callback)
end

-- Execute all cleanup callbacks
local function execute_cleanup()
	for _, callback in ipairs(State.cleanup_callbacks) do
		local ok, err = pcall(callback)
		if not ok then
			vim.notify("Cleanup error: " .. tostring(err), vim.log.levels.WARN)
		end
	end
	State.cleanup_callbacks = {}
end

-- Validate user configuration
local function validate_config(user_config)
	user_config = user_config or {}

	-- Merge with secure defaults
	local config = deps["claude-code-ide.config"].merge_with_defaults(user_config)

	-- Validate configuration integrity
	local validation_result = deps["claude-code-ide.config"].validate(config)
	if not validation_result.valid then
		error("Configuration validation failed: " .. table.concat(validation_result.errors, ", "))
	end

	return config
end

-- Safe terminal management with error boundaries
function M.toggle()
	if not State.initialized then
		vim.notify("Plugin not initialized. Run require('claude-code-ide').setup() first", vim.log.levels.ERROR)
		return false
	end

	local ok, result = pcall(function()
		-- Ensure server is running before opening terminal
		if not State.server then
			deps["claude-code-ide.log"].info("MAIN", "Starting server before opening terminal")
			local server = M.start_server()
			if not server then
				error("Failed to start server")
			end
			-- Give server a moment to initialize
			vim.defer_fn(function()
				if snacks then
					M._toggle_snacks_terminal()
				else
					M._toggle_basic_terminal()
				end
			end, 100)
			return true
		end

		-- Prefer snacks if available, fallback to basic terminal
		if snacks then
			return M._toggle_snacks_terminal()
		else
			return M._toggle_basic_terminal()
		end
	end)

	if not ok then
		vim.notify("Terminal toggle failed: " .. tostring(result), vim.log.levels.ERROR)
		deps["claude-code-ide.log"].error("MAIN", "Terminal toggle error", { error = result })
		return false
	end

	return result
end

-- Snacks-based terminal implementation
function M._toggle_snacks_terminal()
	-- If terminal exists and is visible, hide it
	if State.terminal and State.terminal.win and State.terminal.win:valid() then
		State.terminal:hide()
		deps["claude-code-ide.events"].emit("TerminalHidden")
		return true
	end

	-- Create or show terminal
	if not State.terminal then
		State.terminal = snacks.terminal("claude --ide --debug", {
			win = {
				position = "right",
				width = 0.4,
			},
		})

		-- Register cleanup
		register_cleanup(function()
			if State.terminal then
				State.terminal:close()
				State.terminal = nil
			end
		end)

		deps["claude-code-ide.events"].emit("TerminalCreated")
	else
		State.terminal:show()
		deps["claude-code-ide.events"].emit("TerminalShown")
	end

	return true
end

-- Basic terminal fallback implementation
function M._toggle_basic_terminal()
	-- Simple implementation when snacks is not available
	vim.cmd("vsplit | terminal claude --ide --debug")
	deps["claude-code-ide.events"].emit("TerminalCreated", { type = "basic" })
	return true
end

-- Comprehensive server management with error recovery
function M.start_server(config_override)
	if State.server then
		vim.notify("Server already running", vim.log.levels.WARN)
		return State.server
	end

	local server_config = config_override or State.config

	local server_module = load_dependency("claude-code-ide.server", true)
	local server, err = server_module.start(server_config)

	if not server then
		local error_msg = "Server start failed: " .. (err or "unknown error")
		vim.notify(error_msg, vim.log.levels.ERROR)
		deps["claude-code-ide.log"].error("MAIN", "Server start error", { error = err })
		return nil
	end

	State.server = server
	deps["claude-code-ide.events"].emit("ServerStarted", { server = server })

	-- Register cleanup
	register_cleanup(function()
		if State.server then
			M.stop_server()
		end
	end)

	return server
end

-- Safe server shutdown
function M.stop_server()
	if not State.server then
		return true
	end

	local ok, result = pcall(function()
		return State.server:stop()
	end)

	if ok then
		deps["claude-code-ide.events"].emit("ServerStopped")
		State.server = nil
		return true
	else
		vim.notify("Server stop failed: " .. tostring(result), vim.log.levels.WARN)
		return false
	end
end

-- Get comprehensive plugin status
function M.status()
	return {
		initialized = State.initialized,
		server_running = State.server ~= nil,
		terminal_active = State.terminal ~= nil,
		config = State.config and {
			server = State.config.server,
			ui = { enabled = State.config.ui.enabled },
		} or nil,
		environment = {
			neovim_version = vim.version(),
			dependencies = vim.tbl_keys(deps),
		},
	}
end

-- Main setup function with comprehensive initialization
function M.setup(opts)
	-- Prevent multiple initialization
	if State.initialized then
		vim.notify("Plugin already initialized", vim.log.levels.WARN)
		return true
	end

	local ok, result = pcall(function()
		-- Validate environment
		validate_environment()

		-- Validate and merge configuration
		State.config = validate_config(opts)

		-- Configure logging level from config
		if State.config.logging and State.config.logging.level then
			local log = deps["claude-code-ide.log"]
			if log.levels[State.config.logging.level] then
				log.set_level(log.levels[State.config.logging.level])
			end
		end

		-- Setup event system
		deps["claude-code-ide.events"].setup(State.config.events)

		-- Setup resources system
		local resources = load_dependency("claude-code-ide.resources", false)
		if resources and resources.setup then
			resources.setup()
		end

		-- Setup editor notifications
		local notifications = load_dependency("claude-code-ide.editor_notifications", false)
		if notifications and notifications.setup then
			notifications.setup()
		end

		-- Auto-start server if configured
		if State.config.server.auto_start then
			M.start_server()
		end

		-- Setup keymaps if enabled
		if State.config.keymaps.enabled then
			M.setup_keymaps()
		end

		-- Register VimLeavePre cleanup
		vim.api.nvim_create_autocmd("VimLeavePre", {
			callback = execute_cleanup,
			desc = "Claude Code IDE cleanup",
		})

		State.initialized = true
		deps["claude-code-ide.events"].emit("Initialized", State.config)

		return true
	end)

	if not ok then
		vim.notify("Setup failed: " .. tostring(result), vim.log.levels.ERROR)
		execute_cleanup()
		return false
	end

	deps["claude-code-ide.log"].info("MAIN", "Plugin initialized successfully")
	return true
end

-- Setup keymaps with validation
function M.setup_keymaps()
	local prefix = State.config.keymaps.prefix
	local mappings = State.config.keymaps.mappings

	-- Validate keymap configuration
	if not prefix or not mappings then
		vim.notify("Invalid keymap configuration", vim.log.levels.WARN)
		return
	end

	-- Setup main toggle
	vim.keymap.set("n", prefix .. mappings.toggle, M.toggle, {
		desc = "Toggle Claude terminal",
		silent = true,
	})

	-- Setup additional mappings
	if mappings.status then
		vim.keymap.set("n", prefix .. mappings.status, function()
			vim.print(M.status())
		end, {
			desc = "Show Claude status",
			silent = true,
		})
	end
end

-- Graceful shutdown
function M.shutdown()
	if not State.initialized then
		return true
	end

	deps["claude-code-ide.log"].info("MAIN", "Initiating shutdown")
	execute_cleanup()
	State.initialized = false

	return true
end

-- Export public API
M.start = M.start_server
M.stop = M.stop_server

return M
