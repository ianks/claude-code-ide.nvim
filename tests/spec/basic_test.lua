-- Basic sanity tests to verify test environment is working

describe("Basic Test Environment", function()
	it("should be able to run simple tests", function()
		assert.equals(1, 1)
		assert.is_true(true)
		assert.is_false(false)
	end)

	it("should have test utilities available", function()
		assert.truthy(_G.test_utils)
		assert.equals("function", type(_G.test_utils.wait))
		assert.equals("function", type(_G.test_utils.reset_modules))
	end)

	it("should have mocked vim functions", function()
		assert.equals("function", type(vim.wait))
		assert.equals("function", type(vim.schedule))
		assert.equals("function", type(vim.defer_fn))
	end)

	it("should be able to load plugin modules", function()
		local success, config = pcall(require, "claude-code-ide.config")
		assert.is_true(success)
		assert.truthy(config)
	end)

	it("should have safe timeouts", function()
		local start_time = vim.loop.hrtime()

		-- This should timeout quickly instead of hanging
		_G.test_utils.wait(50, function()
			return false
		end)

		local elapsed = (vim.loop.hrtime() - start_time) / 1e6
		assert.is_true(elapsed < 100) -- Should complete within 100ms
	end)

	it("should handle module resets", function()
		-- Load a module
		local config = require("claude-code-ide.config")
		assert.truthy(config)

		-- Reset modules
		_G.test_utils.reset_modules("claude%-code%-ide")

		-- Should be able to load again
		local config2 = require("claude-code-ide.config")
		assert.truthy(config2)
	end)

	it("should handle errors gracefully", function()
		assert.has_no_error(function()
			pcall(function()
				error("test error")
			end)
		end)
	end)
end)
