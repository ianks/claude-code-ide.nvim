-- Tests for configuration management

local config = require("claude-code-ide.config")

describe("Configuration System", function()
	-- Save original config
	local original_config

	before_each(function()
		-- Reset to defaults before each test
		config.reset()
		original_config = config.get()
	end)

	after_each(function()
		-- Restore original config
		config.reset()
	end)

	describe("Default Configuration", function()
		it("should have all required sections", function()
			local defaults = config.get_defaults()

			assert.truthy(defaults.server)
			assert.truthy(defaults.lock_file)
			assert.truthy(defaults.ui)
			assert.truthy(defaults.queue)
			assert.truthy(defaults.keymaps)
			assert.truthy(defaults.autocmds)
			assert.truthy(defaults.features)
			assert.truthy(defaults.debug)
		end)

		it("should have valid default server settings", function()
			local defaults = config.get_defaults()

			assert.equals("127.0.0.1", defaults.server.host)
			assert.equals(0, defaults.server.port)
			assert.equals(10000, defaults.server.port_range[1])
			assert.equals(65535, defaults.server.port_range[2])
			assert.is_true(defaults.server.enabled)
			assert.is_false(defaults.server.auto_start)
		end)

		it("should have valid default UI settings", function()
			local defaults = config.get_defaults()

			assert.equals("right", defaults.ui.conversation.position)
			assert.equals(80, defaults.ui.conversation.width)
			assert.equals("rounded", defaults.ui.conversation.border)
			assert.is_true(defaults.ui.conversation.wrap)
			assert.is_true(defaults.ui.progress.enabled)
			assert.is_true(defaults.ui.notifications.enabled)
		end)

		it("should have valid default queue settings", function()
			local defaults = config.get_defaults()

			assert.equals(3, defaults.queue.max_concurrent)
			assert.equals(100, defaults.queue.max_queue_size)
			assert.equals(30000, defaults.queue.timeout_ms)
			assert.is_true(defaults.queue.rate_limit.enabled)
			assert.equals(30, defaults.queue.rate_limit.max_requests)
		end)
	end)

	describe("Configuration Setup", function()
		it("should merge user config with defaults", function()
			local user_config = {
				server = {
					port = 12345,
					auto_start = false,
				},
				ui = {
					conversation = {
						width = 100,
					},
				},
			}

			config.setup(user_config)
			local merged = config.get()

			-- User settings applied
			assert.equals(12345, merged.server.port)
			assert.is_false(merged.server.auto_start)
			assert.equals(100, merged.ui.conversation.width)

			-- Defaults preserved
			assert.equals("127.0.0.1", merged.server.host)
			assert.equals("right", merged.ui.conversation.position)
			assert.is_true(merged.queue.rate_limit.enabled)
		end)

		it("should create required directories", function()
			-- Mock vim.fn.mkdir
			local mkdir_calls = {}
			vim.fn.mkdir = function(dir, flags)
				table.insert(mkdir_calls, { dir = dir, flags = flags })
			end

			config.setup({
				features = {
					cache = { enabled = true },
					sessions = { auto_save = true },
				},
			})

			-- Should create lock file dir, cache dir, and session dir
			assert.equals(3, #mkdir_calls)
		end)
	end)

	describe("Configuration Validation", function()
		it("should validate server settings", function()
			local valid, errors = config.validate({
				server = {
					port = 70000, -- Invalid: > 65535
					host = "invalid-host", -- Invalid: not IP
				},
			})

			assert.is_false(valid)
			assert.equals(2, #errors)
			-- Check that errors contain the expected messages
			local has_port_error = false
			local has_host_error = false
			for _, err in ipairs(errors) do
				if err:match("port") then
					has_port_error = true
				end
				if err:match("host") then
					has_host_error = true
				end
			end
			assert.is_true(has_port_error)
			assert.is_true(has_host_error)
		end)

		it("should validate UI settings", function()
			local valid, errors = config.validate({
				ui = {
					conversation = {
						position = "invalid", -- Invalid enum
						width = 500, -- Invalid: > 300
						border = "invalid", -- Invalid enum
					},
				},
			})

			assert.is_false(valid)
			assert.equals(3, #errors)
		end)

		it("should validate queue settings", function()
			local valid, errors = config.validate({
				queue = {
					max_concurrent = 20, -- Invalid: > 10
					max_queue_size = 5, -- Invalid: < 10
					timeout_ms = 500, -- Invalid: < 1000
				},
			})

			assert.is_false(valid)
			assert.equals(3, #errors)
		end)

		it("should accept valid configuration", function()
			local valid, errors = config.validate({
				server = {
					port = 8080,
					host = "127.0.0.1",
				},
				ui = {
					conversation = {
						position = "left",
						width = 120,
						border = "single",
					},
				},
				queue = {
					max_concurrent = 5,
					max_queue_size = 200,
					timeout_ms = 60000,
				},
			})

			assert.is_true(valid)
			assert.equals(0, #errors)
		end)

		it("should fall back to defaults on validation errors", function()
			-- Mock notify to suppress error output
			local notify = require("claude-code-ide.ui.notify")
			local original_error = notify.error
			local error_count = 0
			notify.error = function()
				error_count = error_count + 1
			end

			config.setup({
				server = {
					port = 70000, -- Invalid
				},
			})

			local current = config.get()
			assert.equals(0, current.server.port) -- Default value
			assert.is_true(error_count > 0)

			-- Restore
			notify.error = original_error
		end)
	end)

	describe("Configuration Access", function()
		it("should get configuration values by path", function()
			config.setup({
				ui = {
					conversation = {
						width = 123,
					},
				},
			})

			assert.equals(123, config.get("ui.conversation.width"))
			assert.equals("127.0.0.1", config.get("server.host"))
			assert.truthy(config.get("queue"))
			assert.is_nil(config.get("invalid.path"))
		end)

		it("should get entire configuration without path", function()
			local cfg = config.get()

			assert.equals("table", type(cfg))
			assert.truthy(cfg.server)
			assert.truthy(cfg.ui)
			assert.truthy(cfg.queue)
		end)

		it("should set configuration values by path", function()
			config.set("ui.conversation.width", 150)
			assert.equals(150, config.get("ui.conversation.width"))

			config.set("server.port", 9999)
			assert.equals(9999, config.get("server.port"))

			-- Create nested path if not exists
			config.set("custom.nested.value", "test")
			assert.equals("test", config.get("custom.nested.value"))
		end)
	end)

	describe("Configuration Persistence", function()
		it("should save configuration to file", function()
			-- Mock file operations
			local saved_content = nil
			_G.io = {
				open = function(filepath, mode)
					if mode == "w" then
						return {
							write = function(self, content)
								saved_content = content
							end,
							close = function() end,
						}
					end
				end,
			}

			config.set("ui.conversation.width", 200)
			local success = config.save()

			assert.is_true(success)
			assert.truthy(saved_content)

			local saved = vim.json.decode(saved_content)
			assert.equals(200, saved.ui.conversation.width)
		end)

		it("should load configuration from file", function()
			-- Mock file operations
			local test_config = {
				server = { port = 7777 },
				ui = { conversation = { width = 250 } },
			}

			_G.io = {
				open = function(filepath, mode)
					if mode == "r" then
						return {
							read = function()
								return vim.json.encode(test_config)
							end,
							close = function() end,
						}
					end
				end,
			}

			local success = config.load()

			assert.is_true(success)
			assert.equals(7777, config.get("server.port"))
			assert.equals(250, config.get("ui.conversation.width"))
		end)

		it("should handle load errors gracefully", function()
			-- Mock file not found
			_G.io = {
				open = function()
					return nil
				end,
			}

			local success = config.load("nonexistent.json")
			assert.is_false(success)

			-- Mock invalid JSON
			_G.io = {
				open = function()
					return {
						read = function()
							return "invalid json{"
						end,
						close = function() end,
					}
				end,
			}

			-- Mock notify to suppress error
			local notify = require("claude-code-ide.ui.notify")
			local original_error = notify.error
			notify.error = function() end

			success = config.load()
			assert.is_false(success)

			-- Restore
			notify.error = original_error
		end)
	end)

	describe("Configuration Reset", function()
		it("should reset to defaults", function()
			config.set("server.port", 9999)
			config.set("ui.conversation.width", 200)

			config.reset()

			assert.equals(0, config.get("server.port"))
			assert.equals(80, config.get("ui.conversation.width"))
		end)
	end)

	describe("Backward Compatibility", function()
		it("should support old _validate function", function()
			-- Should not error with valid config
			local valid_config = {
				server = { port_range = { 1000, 2000 } },
				ui = { conversation = { position = "right" } },
			}

			assert.has_no_error(function()
				config._validate(valid_config)
			end)

			-- Should error with invalid port range
			local invalid_config = {
				server = { port_range = { 2000, 1000 } },
				ui = { conversation = { position = "right" } },
			}

			assert.has_error(function()
				config._validate(invalid_config)
			end)
		end)
	end)
end)
