-- Minimal init.lua for running tests with timeouts and better async handling
-- Usage: nvim --headless -u tests/minimal_init.lua -c "PlenaryBustedDirectory tests/spec/ {minimal_init = 'tests/minimal_init.lua'}"

-- Set test mode flag
vim.g.claude_code_test_mode = true

-- Configure test timeouts (prevent hanging tests)
vim.g.plenary_test_timeout = 5000 -- 5 second timeout for each test

-- Set up package path
local plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
local plugin_path = vim.fn.getcwd()

vim.opt.rtp:prepend(plenary_path)
vim.opt.rtp:prepend(plugin_path)

-- Load required plugins
vim.cmd("runtime! plugin/plenary.vim")

-- Configure Neovim for testing
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.hidden = true
vim.opt.termguicolors = true

-- Set up globals for testing
_G.__TEST = true

-- Mock vim.wait with timeout to prevent hanging
local original_wait = vim.wait
vim.wait = function(timeout, callback, interval, fast_only)
	-- Ensure we never wait longer than 1 second in tests
	local safe_timeout = math.min(timeout or 1000, 1000)
	return original_wait(safe_timeout, callback, interval or 10, fast_only)
end

-- Mock vim.defer_fn with timeout protection
local original_defer_fn = vim.defer_fn
vim.defer_fn = function(fn, timeout)
	-- Cap deferred function timeouts to prevent hanging
	local safe_timeout = math.min(timeout or 100, 100)
	return original_defer_fn(fn, safe_timeout)
end

-- Mock external dependencies that might not be available in test environment
package.loaded["snacks"] = package.loaded["snacks"]
	or {
		win = function()
			return { close = function() end }
		end,
		layout = function()
			return { close = function() end }
		end,
		notifier = { notify = function() end },
		input = function() end,
		animate = function() end,
		terminal = {
			toggle = function()
				return { id = 1 }
			end,
			get = function()
				return nil
			end,
			close = function() end,
		},
	}

package.loaded["mini.icons"] = package.loaded["mini.icons"] or {
	get = function()
		return "", "", ""
	end,
}

-- Mock plenary async to prevent hanging
package.loaded["plenary.async"] = package.loaded["plenary.async"]
	or {
		run = function(fn, callback)
			-- Run async functions synchronously in tests
			local success, result = pcall(fn)
			if callback then
				callback(success, result)
			end
			return success, result
		end,
		void = function(fn)
			return function(...)
				return fn(...)
			end
		end,
		wrap = function(fn, argc)
			return fn
		end,
	}

-- Override vim.schedule to run immediately in tests
local original_schedule = vim.schedule
vim.schedule = function(fn)
	-- Run immediately instead of scheduling to prevent hanging
	if type(fn) == "function" then
		local success, err = pcall(fn)
		if not success then
			print("Scheduled function error:", err)
		end
	end
end

-- Test utility functions
_G.test_utils = {
	-- Safe wait that times out quickly
	wait = function(timeout, condition)
		timeout = timeout or 100 -- Default 100ms
		local start = vim.loop.hrtime()
		while (vim.loop.hrtime() - start) / 1e6 < timeout do
			if condition and condition() then
				return true
			end
			vim.wait(10) -- Small delay
		end
		return false
	end,

	-- Reset all package modules for clean test state
	reset_modules = function(pattern)
		pattern = pattern or "claude%-code%-ide"
		for module_name in pairs(package.loaded) do
			if module_name:match(pattern) then
				package.loaded[module_name] = nil
			end
		end
	end,

	-- Mock events system that doesn't hang
	mock_events = function()
		return {
			setup = function() end,
			on = function(event, callback) end,
			emit = function(event, data) end,
			off = function(id)
				return true
			end,
			shutdown = function() end,
			get_stats = function()
				return { events_emitted = 0, events_handled = 0, errors = 0 }
			end,
			health_check = function()
				return { healthy = true, details = {} }
			end,
		}
	end,
}

-- Ensure required modules are loaded
require("plenary.busted")

-- Configure busted timeout
if _G.busted then
	_G.busted.set_defer_print(false)
end

print("Test environment initialized with timeouts and safety measures")
