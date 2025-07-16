-- Minimal init.lua for integration tests
-- Uses real components with minimal mocking

-- Add project root to runtimepath
local root = vim.fn.fnamemodify(vim.fn.resolve(vim.fn.expand("<sfile>")), ":p:h:h")
vim.opt.runtimepath:prepend(root)

-- Add test helpers to path
package.path = package.path .. ";" .. root .. "/tests/?.lua"
package.path = package.path .. ";" .. root .. "/tests/integration/?.lua"

-- Load plenary
local plenary_path = vim.fn.stdpath("data") .. "/site/pack/packer/start/plenary.nvim"
if vim.fn.isdirectory(plenary_path) == 0 then
	-- Try lazy.nvim path
	plenary_path = vim.fn.stdpath("data") .. "/lazy/plenary.nvim"
end
if vim.fn.isdirectory(plenary_path) == 1 then
	vim.opt.runtimepath:prepend(plenary_path)
else
	error("plenary.nvim not found. Please install it first.")
end

-- Mock only external UI dependencies that we can't control in tests
package.loaded["snacks"] = {
	win = function(opts)
		return {
			win = vim.api.nvim_create_win(vim.api.nvim_create_buf(false, true), false, {
				relative = "editor",
				width = opts.width or 80,
				height = opts.height or 20,
				row = 0,
				col = 0,
			}),
			close = function() end,
			valid = function()
				return true
			end,
		}
	end,
	layout = function(opts)
		return {
			close = function() end,
			wins = { original = { win = 1 }, changes = { win = 2 } },
		}
	end,
	notifier = {
		notify = function(msg, opts)
			-- Just print in tests
			print(string.format("[%s] %s", opts and opts.level or "info", msg))
		end,
	},
	input = function(opts, callback)
		-- Return default value in tests
		callback(opts.default or "")
	end,
	animate = function()
		return { stop = function() end }
	end,
}

package.loaded["mini.icons"] = {
	get = function()
		return "📄", "File", "#ffffff"
	end,
}

-- Set test environment flag
_G.__TEST = true

-- Load the plugin
require("claude-code")

-- Configure for testing
vim.g.claude_code_debug = false -- Set to true for debugging

-- Disable some vim features that interfere with tests
vim.opt.swapfile = false
vim.opt.backup = false
vim.opt.writebackup = false
vim.opt.hidden = true

-- Helper to run integration tests
function _G.run_integration_tests(pattern)
	-- Set longer timeout for integration tests
	vim.env.PLENARY_TEST_TIMEOUT = "10000"

	-- Run each integration test file
	local test_files = {
		"tests/integration/server_integration_spec.lua",
		"tests/integration/tools_integration_spec.lua",
		"tests/integration/session_integration_spec.lua",
	}

	for _, file in ipairs(test_files) do
		if vim.fn.filereadable(file) == 1 then
			print("Running: " .. file)
			require("plenary.busted").run(file)
		end
	end
end