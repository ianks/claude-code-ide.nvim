-- Comprehensive tests for the main plugin initialization system

local init = require("claude-code-ide.init")

describe("Plugin Initialization", function()
	-- Mock dependencies to avoid external requirements during testing
	local mock_plenary, mock_snacks, mock_mini

	before_each(function()
		-- Reset any global state
		package.loaded["claude-code-ide.init"] = nil
		package.loaded["claude-code-ide.config"] = nil
		package.loaded["claude-code-ide.events"] = nil
		package.loaded["claude-code-ide.server.init"] = nil

		-- Create mocks for external dependencies
		mock_plenary = {
			async = {
				run = function(fn)
					fn()
				end,
				void = function(fn)
					return fn
				end,
			},
		}

		mock_snacks = {
			terminal = {
				toggle = function()
					return { id = 1 }
				end,
				get = function()
					return nil
				end,
				close = function() end,
			},
			notifier = {
				notify = function() end,
			},
		}

		mock_mini = {
			get = function()
				return "", "", ""
			end,
		}

		-- Override package.loaded to provide mocks
		package.loaded["plenary.async"] = mock_plenary.async
		package.loaded["snacks"] = mock_snacks
		package.loaded["mini.icons"] = mock_mini

		-- Reload module after mocking
		init = require("claude-code-ide.init")
	end)

	after_each(function()
		-- Clean up mocks
		package.loaded["plenary.async"] = nil
		package.loaded["snacks"] = nil
		package.loaded["mini.icons"] = nil
	end)

	describe("Dependency Management", function()
		it("should validate required dependencies on setup", function()
			-- Test with all dependencies available
			assert.has_no_error(function()
				init.setup({})
			end)
		end)

		it("should handle missing optional dependencies gracefully", function()
			-- Remove snacks and test fallback
			package.loaded["snacks"] = nil

			assert.has_no_error(function()
				init.setup({})
			end)
		end)

		it("should error on missing required dependencies", function()
			-- Remove plenary (required dependency)
			package.loaded["plenary.async"] = nil

			assert.has_error(function()
				init.setup({})
			end, "Missing required dependency")
		end)

		it("should warn about missing optional dependencies", function()
			local warnings = {}
			local original_notify = vim.notify
			vim.notify = function(msg, level)
				if level == vim.log.levels.WARN then
					table.insert(warnings, msg)
				end
			end

			-- Remove mini.icons (optional)
			package.loaded["mini.icons"] = nil

			init.setup({})
			vim.notify = original_notify

			assert.is_true(#warnings > 0)
			assert.truthy(vim.tbl_filter(function(w)
				return w:find("mini.icons")
			end, warnings)[1])
		end)
	end)

	describe("Configuration Setup", function()
		it("should setup with default configuration", function()
			init.setup()

			local config = require("claude-code-ide.config")
			local current_config = config.get()

			assert.truthy(current_config)
			assert.truthy(current_config.server)
			assert.truthy(current_config.logging)
			assert.truthy(current_config.ui)
		end)

		it("should merge user configuration with defaults", function()
			local user_config = {
				server = {
					port = 9999,
					auto_start = true,
				},
				ui = {
					theme = "dark",
				},
			}

			init.setup(user_config)

			local config = require("claude-code-ide.config")
			local current_config = config.get()

			-- User values should be applied
			assert.equals(9999, current_config.server.port)
			assert.is_true(current_config.server.auto_start)
			assert.equals("dark", current_config.ui.theme)

			-- Defaults should be preserved
			assert.equals("127.0.0.1", current_config.server.host)
		end)

		it("should validate configuration during setup", function()
			local invalid_config = {
				server = {
					port = "invalid_port", -- Should be number
					max_connections = -1, -- Should be positive
				},
			}

			assert.has_error(function()
				init.setup(invalid_config)
			end)
		end)

		it("should emit setup completion event", function()
			local events = require("claude-code-ide.events")
			events.setup()

			local setup_events = {}
			events.on("PluginInitialized", function(data)
				table.insert(setup_events, data)
			end)

			init.setup({})

			vim.wait(50) -- Wait for async event

			assert.equals(1, #setup_events)
			assert.truthy(setup_events[1].version)
			assert.truthy(setup_events[1].config_loaded)
		end)
	end)

	describe("Server Lifecycle Management", function()
		before_each(function()
			-- Mock server module
			local mock_server = {
				start = function()
					return true
				end,
				stop = function()
					return true
				end,
				is_running = function()
					return false
				end,
				health_check = function()
					return { healthy = true }
				end,
			}
			package.loaded["claude-code-ide.server.init"] = mock_server
		end)

		it("should provide server start functionality", function()
			init.setup({})

			assert.has_no_error(function()
				init.start_server()
			end)
		end)

		it("should provide server stop functionality", function()
			init.setup({})

			assert.has_no_error(function()
				init.stop_server()
			end)
		end)

		it("should check server status", function()
			init.setup({})

			local is_running = init.is_server_running()
			assert.equals("boolean", type(is_running))
		end)

		it("should handle server start errors gracefully", function()
			-- Mock server that fails to start
			local failing_server = {
				start = function()
					error("Failed to start server")
				end,
				stop = function()
					return true
				end,
				is_running = function()
					return false
				end,
			}
			package.loaded["claude-code-ide.server.init"] = failing_server

			init.setup({})

			-- Should not crash the plugin
			assert.has_no_error(function()
				init.start_server()
			end)
		end)

		it("should auto-start server when configured", function()
			local start_called = false
			local auto_start_server = {
				start = function()
					start_called = true
					return true
				end,
				stop = function()
					return true
				end,
				is_running = function()
					return false
				end,
			}
			package.loaded["claude-code-ide.server.init"] = auto_start_server

			init.setup({
				server = {
					auto_start = true,
				},
			})

			vim.wait(50) -- Wait for async start
			assert.is_true(start_called)
		end)
	end)

	describe("Terminal Integration", function()
		it("should toggle terminal using snacks when available", function()
			local toggle_called = false
			mock_snacks.terminal.toggle = function()
				toggle_called = true
				return { id = 1 }
			end

			init.setup({})
			init.toggle_terminal()

			assert.is_true(toggle_called)
		end)

		it("should fallback to builtin terminal when snacks unavailable", function()
			-- Remove snacks terminal
			package.loaded["snacks"] = { notifier = { notify = function() end } }

			init.setup({})

			-- Should not error even without snacks terminal
			assert.has_no_error(function()
				init.toggle_terminal()
			end)
		end)

		it("should handle terminal errors gracefully", function()
			mock_snacks.terminal.toggle = function()
				error("Terminal error")
			end

			init.setup({})

			-- Should not crash
			assert.has_no_error(function()
				init.toggle_terminal()
			end)
		end)

		it("should create terminal with correct configuration", function()
			local terminal_config = nil
			mock_snacks.terminal.toggle = function(cmd, opts)
				terminal_config = opts
				return { id = 1 }
			end

			init.setup({
				terminal = {
					shell = "zsh",
					size = 20,
				},
			})

			init.toggle_terminal()

			assert.truthy(terminal_config)
			assert.equals(20, terminal_config.win.height)
		end)
	end)

	describe("Health Check System", function()
		before_each(function()
			-- Mock all subsystems for health check
			package.loaded["claude-code-ide.server.init"] = {
				health_check = function()
					return { healthy = true, details = { running = false } }
				end,
			}
		end)

		it("should provide comprehensive health check", function()
			init.setup({})

			local health = init.health_check()

			assert.truthy(health)
			assert.truthy(health.plugin)
			assert.truthy(health.config)
			assert.truthy(health.events)
			assert.truthy(health.server)
			assert.truthy(health.overall_healthy)
		end)

		it("should report plugin health correctly", function()
			init.setup({})

			local health = init.health_check()

			assert.is_true(health.plugin.healthy)
			assert.truthy(health.plugin.version)
			assert.truthy(health.plugin.initialized)
		end)

		it("should aggregate health from all subsystems", function()
			-- Mock unhealthy subsystem
			local unhealthy_config = {
				health_check = function()
					return { healthy = false, details = { errors = { "Config error" } } }
				end,
			}
			package.loaded["claude-code-ide.config"] = unhealthy_config

			init.setup({})

			local health = init.health_check()

			assert.is_false(health.overall_healthy)
			assert.is_false(health.config.healthy)
		end)

		it("should include dependency status in health check", function()
			init.setup({})

			local health = init.health_check()

			assert.truthy(health.dependencies)
			assert.truthy(health.dependencies.plenary)
			assert.truthy(health.dependencies.snacks)
		end)
	end)

	describe("Keymap Management", function()
		it("should setup default keymaps when enabled", function()
			local keymaps_set = {}
			local original_keymap = vim.keymap.set
			vim.keymap.set = function(mode, lhs, rhs, opts)
				table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
			end

			init.setup({
				keymaps = {
					enabled = true,
				},
			})

			vim.keymap.set = original_keymap

			-- Should have set some keymaps
			assert.is_true(#keymaps_set > 0)

			-- Check for expected keymaps
			local keymap_lhs = vim.tbl_map(function(k)
				return k.lhs
			end, keymaps_set)
			assert.truthy(vim.tbl_contains(keymap_lhs, "<leader>cs")) -- Start server
			assert.truthy(vim.tbl_contains(keymap_lhs, "<leader>ct")) -- Toggle terminal
		end)

		it("should not setup keymaps when disabled", function()
			local keymaps_set = {}
			local original_keymap = vim.keymap.set
			vim.keymap.set = function(mode, lhs, rhs, opts)
				table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
			end

			init.setup({
				keymaps = {
					enabled = false,
				},
			})

			vim.keymap.set = original_keymap

			-- Should not have set any claude-code keymaps
			assert.equals(0, #keymaps_set)
		end)

		it("should allow custom keymap configuration", function()
			local keymaps_set = {}
			local original_keymap = vim.keymap.set
			vim.keymap.set = function(mode, lhs, rhs, opts)
				table.insert(keymaps_set, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
			end

			init.setup({
				keymaps = {
					enabled = true,
					start_server = "<leader>start",
					toggle_terminal = "<F12>",
				},
			})

			vim.keymap.set = original_keymap

			local keymap_lhs = vim.tbl_map(function(k)
				return k.lhs
			end, keymaps_set)
			assert.truthy(vim.tbl_contains(keymap_lhs, "<leader>start"))
			assert.truthy(vim.tbl_contains(keymap_lhs, "<F12>"))
		end)
	end)

	describe("Autocmd Management", function()
		it("should setup autocmds for file operations", function()
			local autocmds_created = {}
			local original_create_autocmd = vim.api.nvim_create_autocmd
			vim.api.nvim_create_autocmd = function(events, opts)
				table.insert(autocmds_created, { events = events, opts = opts })
				return 1
			end

			init.setup({
				autocmds = {
					enabled = true,
				},
			})

			vim.api.nvim_create_autocmd = original_create_autocmd

			-- Should have created autocmds
			assert.is_true(#autocmds_created > 0)

			-- Check for expected events
			local events = vim.tbl_flatten(vim.tbl_map(function(a)
				return a.events
			end, autocmds_created))
			assert.truthy(vim.tbl_contains(events, "BufEnter"))
			assert.truthy(vim.tbl_contains(events, "VimLeavePre"))
		end)

		it("should not setup autocmds when disabled", function()
			local autocmds_created = {}
			local original_create_autocmd = vim.api.nvim_create_autocmd
			vim.api.nvim_create_autocmd = function(events, opts)
				table.insert(autocmds_created, { events = events, opts = opts })
			end

			init.setup({
				autocmds = {
					enabled = false,
				},
			})

			vim.api.nvim_create_autocmd = original_create_autocmd

			assert.equals(0, #autocmds_created)
		end)
	end)

	describe("Error Handling", function()
		it("should handle configuration errors gracefully", function()
			-- Mock config module that throws error
			local failing_config = {
				setup = function()
					error("Config setup failed")
				end,
			}
			package.loaded["claude-code-ide.config"] = failing_config

			-- Should not crash the entire plugin
			assert.has_no_error(function()
				init.setup({})
			end)
		end)

		it("should handle events system errors gracefully", function()
			-- Mock events module that fails
			local failing_events = {
				setup = function()
					error("Events setup failed")
				end,
			}
			package.loaded["claude-code-ide.events"] = failing_events

			assert.has_no_error(function()
				init.setup({})
			end)
		end)

		it("should log errors appropriately", function()
			local error_logs = {}
			local original_notify = vim.notify
			vim.notify = function(msg, level)
				if level == vim.log.levels.ERROR then
					table.insert(error_logs, msg)
				end
			end

			-- Force an error during setup
			package.loaded["claude-code-ide.config"] = {
				setup = function()
					error("Test error")
				end,
			}

			init.setup({})
			vim.notify = original_notify

			assert.is_true(#error_logs > 0)
		end)

		it("should maintain partial functionality on component failure", function()
			-- Fail config but keep events working
			package.loaded["claude-code-ide.config"] = {
				setup = function()
					error("Config failed")
				end,
			}

			init.setup({})

			-- Terminal should still work
			assert.has_no_error(function()
				init.toggle_terminal()
			end)
		end)
	end)

	describe("Module State Management", function()
		it("should prevent multiple initialization", function()
			init.setup({})

			local warnings = {}
			local original_notify = vim.notify
			vim.notify = function(msg, level)
				if level == vim.log.levels.WARN then
					table.insert(warnings, msg)
				end
			end

			-- Second setup should warn
			init.setup({})
			vim.notify = original_notify

			assert.is_true(#warnings > 0)
			assert.truthy(vim.tbl_filter(function(w)
				return w:find("already initialized")
			end, warnings)[1])
		end)

		it("should provide initialization status", function()
			assert.is_false(init.is_initialized())

			init.setup({})

			assert.is_true(init.is_initialized())
		end)

		it("should track plugin version", function()
			init.setup({})

			local version = init.get_version()
			assert.truthy(version)
			assert.equals("string", type(version))
		end)
	end)

	describe("Cleanup and Shutdown", function()
		it("should provide cleanup functionality", function()
			init.setup({})

			assert.has_no_error(function()
				init.cleanup()
			end)
		end)

		it("should cleanup resources on VimLeavePre", function()
			local cleanup_called = false
			local original_cleanup = init.cleanup
			init.cleanup = function()
				cleanup_called = true
				original_cleanup()
			end

			init.setup({
				autocmds = { enabled = true },
			})

			-- Simulate VimLeavePre
			vim.api.nvim_exec_autocmds("VimLeavePre", {})

			init.cleanup = original_cleanup
			assert.is_true(cleanup_called)
		end)

		it("should stop server on cleanup", function()
			local stop_called = false
			package.loaded["claude-code-ide.server.init"] = {
				stop = function()
					stop_called = true
					return true
				end,
				is_running = function()
					return true
				end,
			}

			init.setup({})
			init.cleanup()

			assert.is_true(stop_called)
		end)
	end)

	describe("Plugin API", function()
		it("should expose all public functions", function()
			local expected_functions = {
				"setup",
				"start_server",
				"stop_server",
				"is_server_running",
				"toggle_terminal",
				"health_check",
				"is_initialized",
				"get_version",
				"cleanup",
			}

			for _, func_name in ipairs(expected_functions) do
				assert.equals("function", type(init[func_name]), "Missing function: " .. func_name)
			end
		end)

		it("should not expose internal functions", function()
			-- These should not be accessible from outside
			assert.is_nil(init._setup_dependencies)
			assert.is_nil(init._setup_autocmds)
			assert.is_nil(init._setup_keymaps)
		end)

		it("should provide status information", function()
			init.setup({})

			local status = init.get_status()
			assert.truthy(status)
			assert.truthy(status.initialized)
			assert.truthy(status.version)
			assert.truthy(status.dependencies)
		end)
	end)

	describe("Integration Testing", function()
		it("should work end-to-end with minimal configuration", function()
			assert.has_no_error(function()
				init.setup({})

				-- Test basic functionality
				assert.is_true(init.is_initialized())
				assert.equals("boolean", type(init.is_server_running()))

				local health = init.health_check()
				assert.truthy(health)

				init.toggle_terminal()
				init.cleanup()
			end)
		end)

		it("should work end-to-end with full configuration", function()
			local full_config = {
				server = {
					host = "127.0.0.1",
					port = 8080,
					auto_start = false,
				},
				ui = {
					theme = "dark",
					notifications = {
						enabled = true,
					},
				},
				keymaps = {
					enabled = true,
					start_server = "<leader>start",
				},
				autocmds = {
					enabled = true,
				},
				terminal = {
					shell = "bash",
					size = 15,
				},
			}

			assert.has_no_error(function()
				init.setup(full_config)

				local config = require("claude-code-ide.config")
				local current_config = config.get()

				-- Verify configuration was applied
				assert.equals(8080, current_config.server.port)
				assert.equals("dark", current_config.ui.theme)
				assert.is_false(current_config.server.auto_start)

				init.cleanup()
			end)
		end)
	end)
end)
