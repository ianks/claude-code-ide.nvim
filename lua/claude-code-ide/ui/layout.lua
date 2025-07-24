-- Multi-pane layout management for claude-code-ide.nvim
-- Provides flexible layout configurations using snacks.nvim

local M = {}
local notify = require("claude-code-ide.ui.notify")
local events = require("claude-code-ide.events")

-- Layout presets
M.presets = {
	-- Default: conversation on right
	default = {
		conversation = {
			position = "right",
			width = 80,
			min_width = 60,
			max_width = 120,
		},
		context = {
			enabled = false,
			position = "bottom",
			height = 20,
			min_height = 10,
			max_height = 40,
		},
		preview = {
			enabled = false,
			position = "float",
			width = 100,
			height = 30,
		},
	},

	-- Split: conversation and context
	split = {
		conversation = {
			position = "right",
			width = 60,
			min_width = 50,
			max_width = 80,
		},
		context = {
			enabled = true,
			position = "bottom",
			height = 20,
			min_height = 15,
			max_height = 30,
		},
		preview = {
			enabled = false,
			position = "float",
			width = 100,
			height = 30,
		},
	},

	-- Full: all panes visible
	full = {
		conversation = {
			position = "right",
			width = 50,
			min_width = 40,
			max_width = 70,
		},
		context = {
			enabled = true,
			position = "bottom",
			height = 15,
			min_height = 10,
			max_height = 25,
			relative_to = "editor", -- bottom of editor, not conversation
		},
		preview = {
			enabled = true,
			position = "vsplit",
			width = 0.5, -- 50% of remaining space
			relative_to = "conversation",
		},
	},

	-- Compact: floating windows
	compact = {
		conversation = {
			position = "float",
			width = 80,
			height = 40,
			border = "rounded",
			backdrop = 60,
		},
		context = {
			enabled = true,
			position = "float",
			width = 80,
			height = 20,
			border = "rounded",
			backdrop = false,
			anchor = "SW", -- bottom left
		},
		preview = {
			enabled = false,
		},
	},

	-- Focus: maximized conversation
	focus = {
		conversation = {
			position = "center",
			width = 0.9, -- 90% of screen
			height = 0.9,
			border = "rounded",
			backdrop = 80,
		},
		context = {
			enabled = false,
		},
		preview = {
			enabled = false,
		},
	},
}

-- Active layout state
local state = {
	current_preset = "default",
	windows = {
		conversation = nil,
		context = nil,
		preview = nil,
	},
	config = nil,
}

-- Get window configuration for a pane
local function get_pane_config(pane_name, layout_config)
	local pane = layout_config[pane_name]
	if not pane or pane.enabled == false then
		return nil
	end

	local base_config = {
		title = pane.title,
		border = pane.border or "rounded",
		backdrop = pane.backdrop,
		enter = pane.enter,
		minimal = pane.minimal,
		wo = pane.wo or {},
		bo = pane.bo or {},
	}

	-- Handle position-specific configuration
	if pane.position == "float" or pane.position == "center" then
		base_config.position = pane.position
		base_config.width = pane.width
		base_config.height = pane.height
		base_config.anchor = pane.anchor
	else
		-- Split windows
		base_config.position = pane.position

		-- Width/height can be absolute or relative
		if pane.position == "left" or pane.position == "right" then
			base_config.width = pane.width
			base_config.min_width = pane.min_width
			base_config.max_width = pane.max_width
		else
			base_config.height = pane.height
			base_config.min_height = pane.min_height
			base_config.max_height = pane.max_height
		end
	end

	return base_config
end

-- Apply a layout preset
---@param preset_name string Name of the preset to apply
function M.apply_preset(preset_name)
	local preset = M.presets[preset_name]
	if not preset then
		notify.error("Unknown layout preset: " .. preset_name)
		return
	end

	-- Close existing windows
	M.close_all()

	-- Store current preset
	state.current_preset = preset_name
	state.config = vim.deepcopy(preset)

	-- Emit event
	events.emit(events.events.LAYOUT_CHANGED, {
		preset = preset_name,
		config = state.config,
	})

	-- Silent layout application - no notification needed
end

-- Open a specific pane
---@param pane_name string Name of the pane ("conversation", "context", "preview")
---@param custom_config? table Optional custom configuration
function M.open_pane(pane_name, custom_config)
	local Snacks = require("snacks")

	-- Get configuration
	local config = custom_config or get_pane_config(pane_name, state.config or M.presets.default)
	if not config then
		return nil
	end

	-- Add pane-specific defaults
	if pane_name == "conversation" then
		config = vim.tbl_deep_extend("force", {
			title = " ✳ Claude Code • AI Assistant ",
			ft = "claude_conversation",
			border = "double",
			zindex = 100,
			keys = {
				q = function(self)
					local confirm = vim.fn.confirm("Close Claude Code Assistant?", "&Yes\n&No", 2)
					if confirm == 1 then
						self:close()
					end
				end,
				["<C-l>"] = function()
					M.cycle_layout()
				end,
			},
			wo = {
				winfixwidth = true,
				winhighlight = "Normal:ClaudeConversationNormal,NormalFloat:ClaudeConversationFloat,FloatBorder:ClaudeConversationBorder,CursorLine:ClaudeConversationCursorLine,SignColumn:ClaudeConversationSignColumn",
				statusline = "%#ClaudeStatusLine# ✳ Claude Code %=%#ClaudeStatusLineNC# %{&modified?'[+]':''} ",
			},
			bo = {
				bufhidden = "hide",
			},
		}, config)
	elseif pane_name == "context" then
		config = vim.tbl_deep_extend("force", {
			title = " 📋 Context ",
			ft = "claude_context",
			keys = {
				q = "close",
			},
		}, config)
	elseif pane_name == "preview" then
		config = vim.tbl_deep_extend("force", {
			title = " 👁️ Preview ",
			ft = "claude_preview",
			keys = {
				q = "close",
				["<CR>"] = function(self)
					-- Apply preview changes
					M.apply_preview(self)
				end,
			},
		}, config)
	end

	-- Create window
	local win = Snacks.win(config)
	state.windows[pane_name] = win

	-- Emit event
	events.emit(events.events.PANE_OPENED, {
		pane = pane_name,
		win = win.win,
		buf = win.buf,
	})

	return win
end

-- Close a specific pane
---@param pane_name string Name of the pane to close
function M.close_pane(pane_name)
	local win = state.windows[pane_name]
	if win then
		-- Check if it's a snacks window with valid method
		if type(win.valid) == "function" and win:valid() then
			win:close()
		elseif type(win.close) == "function" then
			-- Fallback for other window types
			win:close()
		end
		state.windows[pane_name] = nil

		-- Emit event
		events.emit(events.events.PANE_CLOSED, {
			pane = pane_name,
		})
	end
end

-- Close all panes
function M.close_all()
	for pane_name, _ in pairs(state.windows) do
		M.close_pane(pane_name)
	end
end

-- Toggle a pane
---@param pane_name string Name of the pane to toggle
function M.toggle_pane(pane_name)
	local win = state.windows[pane_name]
	if win and type(win.valid) == "function" and win:valid() then
		M.close_pane(pane_name)
	else
		M.open_pane(pane_name)
	end
end

-- Cycle through layout presets
function M.cycle_layout()
	local presets = vim.tbl_keys(M.presets)
	table.sort(presets)

	local current_idx = 1
	for i, name in ipairs(presets) do
		if name == state.current_preset then
			current_idx = i
			break
		end
	end

	local next_idx = (current_idx % #presets) + 1
	M.apply_preset(presets[next_idx])
end

-- Resize a pane
---@param pane_name string Name of the pane to resize
---@param dimension "width"|"height" Dimension to resize
---@param delta number Amount to resize by (positive or negative)
function M.resize_pane(pane_name, dimension, delta)
	local win = state.windows[pane_name]
	if not win or (type(win.valid) == "function" and not win:valid()) then
		return
	end

	local current = win.config[dimension] or 0
	local new_size = current + delta

	-- Apply constraints
	local config = state.config[pane_name]
	if config then
		local min_key = "min_" .. dimension
		local max_key = "max_" .. dimension

		if config[min_key] then
			new_size = math.max(new_size, config[min_key])
		end
		if config[max_key] then
			new_size = math.min(new_size, config[max_key])
		end
	end

	-- Update window
	win:update({ [dimension] = new_size })
end

-- Save current layout
---@return table Layout configuration
function M.save_layout()
	local layout = {
		preset = state.current_preset,
		windows = {},
	}

	for pane_name, win in pairs(state.windows) do
		if win and type(win.valid) == "function" and win:valid() then
			-- Try to get actual window dimensions, fall back to config
			local width, height
			local ok, w = pcall(vim.api.nvim_win_get_width, win.win)
			if ok then
				width = w
			else
				width = win.config.width or 80
			end

			ok, h = pcall(vim.api.nvim_win_get_height, win.win)
			if ok then
				height = h
			else
				height = win.config.height or 24
			end

			layout.windows[pane_name] = {
				width = width,
				height = height,
				position = win.config.position,
			}
		end
	end

	return layout
end

-- Restore a saved layout
---@param layout table Saved layout configuration
function M.restore_layout(layout)
	if layout.preset then
		M.apply_preset(layout.preset)
	end

	-- Apply saved window sizes
	if layout.windows then
		for pane_name, win_config in pairs(layout.windows) do
			local win = state.windows[pane_name]
			if win and type(win.valid) == "function" and win:valid() then
				win:update({
					width = win_config.width,
					height = win_config.height,
				})
			end
		end
	end
end

-- Smart layout: automatically adjust based on screen size
function M.smart_layout()
	local width = vim.o.columns
	local height = vim.o.lines

	if width < 120 then
		-- Narrow screen: use compact layout
		M.apply_preset("compact")
	elseif width < 180 then
		-- Medium screen: use default layout
		M.apply_preset("default")
	elseif height < 40 then
		-- Short screen: use split layout
		M.apply_preset("split")
	else
		-- Large screen: use full layout
		M.apply_preset("full")
	end
end

-- Get current layout info
function M.get_info()
	local info = {
		preset = state.current_preset,
		windows = {},
	}

	-- Initialize all pane info
	for pane_name in pairs({ conversation = true, context = true, preview = true }) do
		local win = state.windows[pane_name]
		info.windows[pane_name] = {
			valid = win and type(win.valid) == "function" and win:valid() or false,
			visible = win and type(win.valid) == "function" and win:valid() or false, -- In tests, valid means visible
		}
	end

	return info
end

-- Export state for testing
M._state = state

return M
