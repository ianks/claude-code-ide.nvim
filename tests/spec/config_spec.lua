-- Comprehensive tests for the refactored configuration management system

local config = require("claude-code-ide.config")

describe("Configuration System", function()
	-- Clean up between tests
	after_each(function()
		-- Reset any global state quickly
		if _G.test_utils then
			_G.test_utils.reset_modules("claude%-code%-ide%.config")
		end
		config = require("claude-code-ide.config")
	end)

	describe("Default Configuration", function()
		it("should have comprehensive default configuration", function()
			local defaults = config.defaults

			-- Core sections
			assert.truthy(defaults.server)
			assert.truthy(defaults.lock_file)
			assert.truthy(defaults.logging)
			assert.truthy(defaults.events)
			assert.truthy(defaults.ui)
			assert.truthy(defaults.queue)
			assert.truthy(defaults.cache)
			assert.truthy(defaults.resources)
			assert.truthy(defaults.tools)
			assert.truthy(defaults.keymaps)
			assert.truthy(defaults.terminal)
			assert.truthy(defaults.security)
			assert.truthy(defaults.performance)
			assert.truthy(defaults.debug)
		end)

		it("should have secure server defaults", function()
			local defaults = config.defaults

			assert.equals("127.0.0.1", defaults.server.host) -- Localhost only
			assert.equals(0, defaults.server.port) -- Random port
			assert.equals(false, defaults.server.auto_start) -- Manual start
			assert.equals(30000, defaults.server.timeout_ms)
			assert.equals(5, defaults.server.max_connections)
			assert.truthy(defaults.server.auth.required)
		end)

		it("should have security-first defaults", function()
			local defaults = config.defaults

			assert.equals("600", defaults.lock_file.permissions) -- Owner only
			assert.truthy(defaults.logging.filter_sensitive) -- Filter auth tokens
			assert.truthy(defaults.tools.security.validate_paths)
			assert.truthy(defaults.tools.security.restrict_to_workspace)
			assert.equals(10 * 1024 * 1024, defaults.security.max_file_size)
		end)

		it("should have resource limits configured", function()
			local defaults = config.defaults

			assert.equals(1000, defaults.cache.max_size)
			assert.equals(100, defaults.queue.max_queue_size)
			assert.equals(50 * 1024 * 1024, defaults.cache.memory_limit)
			assert.truthy(defaults.performance.memory_monitoring)
		end)
	end)

	describe("Configuration Validation", function()
		it("should validate valid configuration", function()
			local valid_config = {
				server = {
					host = "127.0.0.1",
					port = 12345,
					max_connections = 10,
				},
				logging = {
					level = "INFO",
					max_size = 1024 * 1024,
				},
			}

			local result = config.validate(config.merge_with_defaults(valid_config))
			assert.is_true(result.valid)
			assert.equals(0, #result.errors)
		end)

		it("should reject invalid server configuration", function()
			local invalid_config = {
				server = {
					host = "invalid-host-format",
					port = -1, -- Invalid port
					max_connections = 0, -- Invalid connection limit
				},
			}

			local result = config.validate(config.merge_with_defaults(invalid_config))
			assert.is_false(result.valid)
			assert.is_true(#result.errors > 0)
		end)

		it("should validate port ranges", function()
			local config_with_port_range = {
				server = {
					port = 5000,
					port_range = { 10000, 65535 },
				},
			}

			local result = config.validate(config.merge_with_defaults(config_with_port_range))
			assert.is_false(result.valid)
			assert.is_true(vim.tbl_contains(
				vim.tbl_map(function(e)
					return e:find("port_range")
				end, result.errors),
				true
			))
		end)

		it("should validate enum values", function()
			local invalid_config = {
				logging = {
					level = "INVALID_LEVEL",
				},
				ui = {
					theme = "invalid_theme",
				},
			}

			local result = config.validate(config.merge_with_defaults(invalid_config))
			assert.is_false(result.valid)
			assert.is_true(#result.errors > 0)
		end)

		it("should validate file permissions format", function()
			local invalid_config = {
				lock_file = {
					permissions = "invalid",
				},
			}

			local result = config.validate(config.merge_with_defaults(invalid_config))
			assert.is_false(result.valid)
			assert.is_true(vim.tbl_contains(
				vim.tbl_map(function(e)
					return e:find("permissions")
				end, result.errors),
				true
			))
		end)

		it("should validate numeric ranges", function()
			local invalid_config = {
				queue = {
					max_concurrent = 0, -- Invalid
					max_queue_size = -1, -- Invalid
					timeout_ms = 0, -- Invalid
				},
			}

			local result = config.validate(config.merge_with_defaults(invalid_config))
			assert.is_false(result.valid)
			assert.is_true(#result.errors >= 3)
		end)
	end)

	describe("Configuration Merging", function()
		it("should merge user config with defaults recursively", function()
			local user_config = {
				server = {
					port = 8080,
					custom_field = "test",
				},
				ui = {
					conversation = {
						width = 100,
					},
				},
			}

			local merged = config.merge_with_defaults(user_config)

			-- User values should override defaults
			assert.equals(8080, merged.server.port)
			assert.equals("test", merged.server.custom_field)
			assert.equals(100, merged.ui.conversation.width)

			-- Defaults should be preserved where not overridden
			assert.equals("127.0.0.1", merged.server.host)
			assert.equals("right", merged.ui.conversation.position)
			assert.truthy(merged.logging)
			assert.truthy(merged.cache)
		end)

		it("should handle deep nested merging", function()
			local user_config = {
				ui = {
					conversation = {
						width = 120,
					},
				},
			}

			local merged = config.merge_with_defaults(user_config)

			-- Should merge deep nested objects
			assert.equals(120, merged.ui.conversation.width)
			assert.equals("right", merged.ui.conversation.position) -- Default preserved
			assert.truthy(merged.ui.layout) -- Other UI sections preserved
		end)
	end)

	describe("Runtime Configuration Access", function()
		it("should setup and access configuration", function()
			local test_config = {
				server = {
					port = 9999,
				},
				debug = {
					enabled = true,
				},
			}

			config.setup(test_config)

			-- Test basic access
			assert.equals(9999, config.get("server.port"))
			assert.equals("127.0.0.1", config.get("server.host"))
			assert.is_true(config.get("debug.enabled"))

			-- Test full config access
			local full_config = config.get()
			assert.truthy(full_config)
			assert.equals(9999, full_config.server.port)
		end)

		it("should return nil for non-existent keys", function()
			config.setup({})

			assert.is_nil(config.get("non.existent.key"))
			assert.is_nil(config.get("server.non_existent"))
		end)

		it("should handle dot notation correctly", function()
			config.setup({
				nested = {
					deep = {
						value = "test",
					},
				},
			})

			assert.equals("test", config.get("nested.deep.value"))
		end)
	end)

	describe("Runtime Configuration Updates", function()
		it("should update configuration at runtime", function()
			config.setup({})

			-- Update a value
			config.set("server.port", 8888)
			assert.equals(8888, config.get("server.port"))

			-- Update nested value
			config.set("ui.conversation.width", 150)
			assert.equals(150, config.get("ui.conversation.width"))
		end)

		it("should validate updates", function()
			config.setup({})

			-- Invalid update should fail
			assert.has_error(function()
				config.set("server.max_connections", -1)
			end)
		end)

		it("should emit configuration change events", function()
			config.setup({})

			local events_received = {}
			local events = require("claude-code-ide.events")
			events.setup({})

			events.on("ConfigurationChanged", function(data)
				table.insert(events_received, data)
			end)

			config.set("server.port", 7777)

			-- Wait for async event
			vim.wait(50)

			assert.equals(1, #events_received)
			assert.equals("server.port", events_received[1].key)
			assert.equals(7777, events_received[1].value)
		end)
	end)

	describe("Directory Creation", function()
		it("should create necessary directories during setup", function()
			local temp_dir = vim.fn.tempname()
			local test_config = {
				lock_file = {
					dir = temp_dir .. "/test_lock",
				},
				logging = {
					file = temp_dir .. "/logs/test.log",
				},
			}

			config.setup(test_config)

			-- Directories should be created
			assert.equals(1, vim.fn.isdirectory(temp_dir .. "/test_lock"))
			assert.equals(1, vim.fn.isdirectory(temp_dir .. "/logs"))

			-- Cleanup
			vim.fn.delete(temp_dir, "rf")
		end)
	end)

	describe("Error Handling", function()
		it("should error on uninitialized access", function()
			-- Reset module state
			package.loaded["claude-code-ide.config"] = nil
			config = require("claude-code-ide.config")

			assert.has_error(function()
				config.get("server.port")
			end, "Configuration not initialized")
		end)

		it("should error on invalid configuration during setup", function()
			local invalid_config = {
				server = {
					max_connections = -1, -- Invalid
				},
			}

			assert.has_error(function()
				config.setup(invalid_config)
			end)
		end)

		it("should error on invalid runtime updates", function()
			config.setup({})

			assert.has_error(function()
				config.set("non.existent.deeply.nested.key", "value")
			end)
		end)
	end)

	describe("Health Check", function()
		it("should provide health status", function()
			config.setup({})

			local health = config.health_check()
			assert.truthy(health.healthy)
			assert.truthy(health.details.initialized)
			assert.is_table(health.details.config_keys)
		end)

		it("should report unhealthy when not initialized", function()
			-- Reset module state
			package.loaded["claude-code-ide.config"] = nil
			config = require("claude-code-ide.config")

			local health = config.health_check()
			assert.is_false(health.healthy)
			assert.is_false(health.details.initialized)
		end)
	end)

	describe("Configuration Schema", function()
		it("should have complete schema definition", function()
			local schema = config.schema
			assert.truthy(schema)

			-- Core sections should be defined
			assert.truthy(schema.server)
			assert.truthy(schema.lock_file)
			assert.truthy(schema.logging)
			assert.truthy(schema.ui)
			assert.truthy(schema.queue)
			assert.truthy(schema.security)
		end)

		it("should define validation rules correctly", function()
			local schema = config.schema

			-- Test different validation types
			assert.equals("boolean", schema.server.enabled)
			assert.equals("string", schema.server.host)
			assert.equals("number", schema.server.port)
			assert.equals("table", type(schema.server.port_range))
		end)
	end)

	describe("Security Configuration", function()
		it("should enforce security limits", function()
			local config_with_large_limits = {
				security = {
					max_file_size = 1000 * 1024 * 1024 * 1024, -- 1TB - too large
				},
			}

			local result = config.validate(config.merge_with_defaults(config_with_large_limits))
			assert.is_false(result.valid)
		end)

		it("should validate security configuration", function()
			local valid_security_config = {
				security = {
					max_file_size = 50 * 1024 * 1024, -- 50MB
					max_path_length = 2048,
				},
			}

			local result = config.validate(config.merge_with_defaults(valid_security_config))
			assert.is_true(result.valid)
		end)
	end)

	describe("Performance Configuration", function()
		it("should validate performance settings", function()
			local perf_config = {
				performance = {
					debounce_ms = 50,
					throttle_ms = 25,
					lazy_loading = true,
					async_operations = true,
				},
			}

			local merged = config.merge_with_defaults(perf_config)
			assert.equals(50, merged.performance.debounce_ms)
			assert.equals(25, merged.performance.throttle_ms)
			assert.is_true(merged.performance.lazy_loading)
		end)
	end)
end)
