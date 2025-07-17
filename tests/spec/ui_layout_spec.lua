-- Tests for multi-pane layout system

local layout = require("claude-code-ide.ui.layout")
local events = require("claude-code-ide.events")

describe("UI Layout", function()
	local captured_events = {}
	local event_handlers = {}

	before_each(function()
		-- Reset state
		layout._state.current_preset = "default"
		layout._state.windows = {
			conversation = nil,
			context = nil,
			preview = nil,
		}

		-- Clear events
		captured_events = {}

		-- Capture layout events
		event_handlers = {
			events.on(events.events.LAYOUT_CHANGED, function(data)
				table.insert(captured_events, { type = "layout_changed", data = data })
			end),
			events.on(events.events.PANE_OPENED, function(data)
				table.insert(captured_events, { type = "pane_opened", data = data })
			end),
			events.on(events.events.PANE_CLOSED, function(data)
				table.insert(captured_events, { type = "pane_closed", data = data })
			end),
		}

		-- Mock Snacks.win
		package.loaded["snacks"] = {
			win = function(config)
				local mock_win = {
					config = config,
					win = 1000 + math.random(100),
					buf = 2000 + math.random(100),
					valid = function(self)
						return true
					end,
					close = function(self)
						self._closed = true
					end,
					update = function(self, opts)
						for k, v in pairs(opts) do
							self.config[k] = v
						end
					end,
				}
				return mock_win
			end,
			notify = function(msg, level, opts)
				return { message = msg, level = level }
			end,
		}
	end)

	after_each(function()
		-- Clean up event handlers
		for _, handler in ipairs(event_handlers) do
			events.off(handler)
		end

		-- Close all panes
		layout.close_all()
	end)

	describe("Layout Presets", function()
		it("should have all required presets", function()
			local presets = vim.tbl_keys(layout.presets)
			assert.truthy(vim.tbl_contains(presets, "default"))
			assert.truthy(vim.tbl_contains(presets, "split"))
			assert.truthy(vim.tbl_contains(presets, "full"))
			assert.truthy(vim.tbl_contains(presets, "compact"))
			assert.truthy(vim.tbl_contains(presets, "focus"))
		end)

		it("should apply presets correctly", function()
			layout.apply_preset("split")

			-- Wait for event
			vim.wait(50)

			assert.equals("split", layout._state.current_preset)
			assert.equals(1, #captured_events)
			assert.equals("layout_changed", captured_events[1].type)
			assert.equals("split", captured_events[1].data.preset)
		end)

		it("should handle invalid preset names", function()
			layout.apply_preset("invalid_preset")

			-- Should not change preset
			assert.equals("default", layout._state.current_preset)
		end)
	end)

	describe("Pane Management", function()
		it("should open conversation pane", function()
			local win = layout.open_pane("conversation")

			assert.truthy(win)
			assert.truthy(win.win)
			assert.truthy(win.buf)
			assert.equals(win, layout._state.windows.conversation)

			-- Check event
			vim.wait(50)
			local found = false
			for _, event in ipairs(captured_events) do
				if event.type == "pane_opened" and event.data.pane == "conversation" then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)

		it("should close panes", function()
			local win = layout.open_pane("conversation")
			layout.close_pane("conversation")

			assert.is_nil(layout._state.windows.conversation)

			-- Check event
			vim.wait(50)
			local found = false
			for _, event in ipairs(captured_events) do
				if event.type == "pane_closed" and event.data.pane == "conversation" then
					found = true
					break
				end
			end
			assert.is_true(found)
		end)

		it("should toggle panes", function()
			-- Initially closed
			assert.is_nil(layout._state.windows.context)

			-- Toggle open
			layout.toggle_pane("context")
			assert.truthy(layout._state.windows.context)

			-- Toggle closed
			layout.toggle_pane("context")
			assert.is_nil(layout._state.windows.context)
		end)

		it("should close all panes", function()
			layout.open_pane("conversation")
			layout.open_pane("context")
			layout.open_pane("preview")

			layout.close_all()

			assert.is_nil(layout._state.windows.conversation)
			assert.is_nil(layout._state.windows.context)
			assert.is_nil(layout._state.windows.preview)
		end)
	end)

	describe("Layout Cycling", function()
		it("should cycle through presets", function()
			local initial = layout._state.current_preset

			layout.cycle_layout()
			local first_change = layout._state.current_preset
			assert.not_equals(initial, first_change)

			-- Cycle through all and back
			local max_cycles = 10
			for i = 1, max_cycles do
				layout.cycle_layout()
				if layout._state.current_preset == initial then
					break
				end
			end

			assert.equals(initial, layout._state.current_preset)
		end)
	end)

	describe("Pane Resizing", function()
		it("should resize panes", function()
			local win = layout.open_pane("conversation")
			local initial_width = win.config.width or 80

			layout.resize_pane("conversation", "width", 10)
			assert.equals(initial_width + 10, win.config.width)

			layout.resize_pane("conversation", "width", -5)
			assert.equals(initial_width + 5, win.config.width)
		end)

		it("should respect min/max constraints", function()
			-- Apply preset with constraints
			layout.apply_preset("default")
			local win = layout.open_pane("conversation")

			-- Try to resize beyond max
			local max_width = layout.presets.default.conversation.max_width
			layout.resize_pane("conversation", "width", 1000)
			assert.equals(max_width, win.config.width)

			-- Try to resize below min
			local min_width = layout.presets.default.conversation.min_width
			layout.resize_pane("conversation", "width", -1000)
			assert.equals(min_width, win.config.width)
		end)
	end)

	describe("Layout Save/Restore", function()
		it("should save current layout", function()
			layout.apply_preset("split")
			layout.open_pane("conversation")
			layout.open_pane("context")

			local saved = layout.save_layout()

			assert.equals("split", saved.preset)
			assert.truthy(saved.windows.conversation)
			assert.truthy(saved.windows.context)
		end)

		it("should restore saved layout", function()
			-- Save current state
			layout.apply_preset("full")
			layout.open_pane("conversation")
			local saved = layout.save_layout()

			-- Change to different layout
			layout.apply_preset("default")
			layout.close_all()

			-- Restore
			layout.restore_layout(saved)

			assert.equals("full", layout._state.current_preset)
		end)
	end)

	describe("Smart Layout", function()
		it("should select layout based on screen size", function()
			-- Mock small screen
			vim.o.columns = 80
			vim.o.lines = 30
			layout.smart_layout()
			assert.equals("compact", layout._state.current_preset)

			-- Mock medium screen
			vim.o.columns = 150
			vim.o.lines = 50
			layout.smart_layout()
			assert.equals("default", layout._state.current_preset)

			-- Mock large screen
			vim.o.columns = 200
			vim.o.lines = 60
			layout.smart_layout()
			assert.equals("full", layout._state.current_preset)

			-- Mock wide but short screen
			vim.o.columns = 200
			vim.o.lines = 30
			layout.smart_layout()
			assert.equals("split", layout._state.current_preset)
		end)
	end)

	describe("Layout Info", function()
		it("should provide current layout info", function()
			layout.apply_preset("split")
			layout.open_pane("conversation")

			local info = layout.get_info()

			assert.equals("split", info.preset)
			assert.is_true(info.windows.conversation.valid)
			assert.is_true(info.windows.conversation.visible)
			assert.is_false(info.windows.context.valid)
		end)
	end)

	describe("Preset Configurations", function()
		it("should have valid configurations for all presets", function()
			for name, preset in pairs(layout.presets) do
				assert.truthy(preset.conversation, name .. " missing conversation config")

				-- Check position types
				local valid_positions = {
					"left",
					"right",
					"top",
					"bottom",
					"float",
					"center",
					"vsplit",
					"split",
				}

				assert.truthy(
					vim.tbl_contains(valid_positions, preset.conversation.position),
					name .. " has invalid conversation position"
				)

				-- Check optional panes
				if preset.context and preset.context.enabled ~= false then
					assert.truthy(preset.context.position)
				end
				if preset.preview and preset.preview.enabled ~= false then
					assert.truthy(preset.preview.position)
				end
			end
		end)
	end)
end)
