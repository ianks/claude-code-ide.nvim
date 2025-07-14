-- Health check for claude-code.nvim
-- Run with :checkhealth claude-code

local M = {}

function M.check()
  vim.health.start("claude-code.nvim")

  -- Check Neovim version
  if vim.fn.has("nvim-0.8.0") == 1 then
    vim.health.ok("Neovim version 0.8.0+ detected")
  else
    vim.health.error("Neovim 0.8.0+ is required", {
      "Please update Neovim to version 0.8.0 or later",
    })
  end

  -- Check required plugins
  local required_plugins = {
    { name = "plenary.nvim", module = "plenary" },
    { name = "snacks.nvim", module = "snacks" },
    { name = "nvim-nio", module = "nio" },
  }

  for _, plugin in ipairs(required_plugins) do
    local ok = pcall(require, plugin.module)
    if ok then
      vim.health.ok(plugin.name .. " is installed")
    else
      vim.health.error(plugin.name .. " is not installed", {
        "Install " .. plugin.name .. " using your package manager",
      })
    end
  end

  -- Check vim.uv availability
  if vim.uv then
    vim.health.ok("vim.uv (libuv) is available")
  else
    vim.health.error("vim.uv is not available", {
      "This is required for WebSocket server functionality",
    })
  end

  -- Check lock file directory
  local config = require("claude-code.config")
  local default_config = config.setup({})
  local lock_dir = vim.fn.fnamemodify(default_config.lock_file.path, ":h")
  
  if vim.fn.isdirectory(lock_dir) == 1 then
    vim.health.ok("Lock file directory exists: " .. lock_dir)
  else
    vim.health.warn("Lock file directory does not exist: " .. lock_dir, {
      "The directory will be created when the server starts",
    })
  end

  -- Check if server is running
  local claude = require("claude-code")
  local status = claude.status()
  
  if status.server_running then
    vim.health.ok("Claude Code server is running")
  else
    vim.health.info("Claude Code server is not running", {
      "Start with :ClaudeCode start",
    })
  end
end

return M