-- Configuration management for claude-code.nvim

local M = {}

-- Default configuration
local defaults = {
  -- Server settings
  server = {
    host = "127.0.0.1",
    port = 0, -- 0 = random available port
    port_range = { 10000, 65535 }, -- Port range to search
  },

  -- Lock file settings
  lock_file = {
    path = vim.fn.expand("~/.claude/nvim/servers.lock"),
    permissions = "600",
  },

  -- UI settings
  ui = {
    -- Snacks.nvim window settings
    conversation = {
      position = "right",
      width = 80,
      border = "rounded",
    },
    notifications = {
      enabled = true,
      level = vim.log.levels.INFO,
    },
  },

  -- Debug settings
  debug = {
    enabled = false,
    log_file = vim.fn.stdpath("state") .. "/claude-code.log",
  },

  -- Keymaps (set to false to disable)
  keymaps = {
    toggle_conversation = "<leader>cc",
    send_selection = "<leader>cs",
    open_diff = "<leader>cd",
  },
}

-- Merge user config with defaults
---@param opts table? User configuration
---@return table config Merged configuration
function M.setup(opts)
  opts = opts or {}
  local config = vim.tbl_deep_extend("force", defaults, opts)

  -- Validate configuration
  M._validate(config)

  -- Ensure directories exist
  local lock_dir = vim.fn.fnamemodify(config.lock_file.path, ":h")
  vim.fn.mkdir(lock_dir, "p")

  return config
end

-- Validate configuration
---@param config table Configuration to validate
function M._validate(config)
  -- Validate port range
  if config.server.port_range[1] > config.server.port_range[2] then
    error("Invalid port range: start must be less than end")
  end

  -- Validate UI position
  local valid_positions = { "left", "right", "top", "bottom", "float" }
  if not vim.tbl_contains(valid_positions, config.ui.conversation.position) then
    error("Invalid conversation position: " .. config.ui.conversation.position)
  end
end

return M