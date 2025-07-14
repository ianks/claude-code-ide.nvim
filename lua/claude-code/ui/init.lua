-- UI components for claude-code.nvim

local M = {}

-- State
local state = {
  conversation_win = nil,
  conversation_buf = nil,
}

-- Toggle conversation window
function M.toggle_conversation()
  if state.conversation_win and vim.api.nvim_win_is_valid(state.conversation_win) then
    M.close_conversation()
  else
    M.open_conversation()
  end
end

-- Open conversation window
function M.open_conversation()
  local Snacks = require("snacks")
  local config = require("claude-code").status().config
  
  if not config then
    vim.notify("Claude Code not initialized", vim.log.levels.ERROR)
    return
  end
  
  -- Get UI config with defaults
  local ui_config = config.ui or {}
  local conv_config = ui_config.conversation or {
    position = "right",
    width = 80,
    border = "rounded"
  }
  
  -- Create buffer if needed
  if not state.conversation_buf or not vim.api.nvim_buf_is_valid(state.conversation_buf) then
    state.conversation_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(state.conversation_buf, "Claude Conversation")
    vim.bo[state.conversation_buf].buftype = "nofile"
    vim.bo[state.conversation_buf].filetype = "markdown"
    
    -- Add some welcome content
    local lines = {
      "# Claude Code Conversation",
      "",
      "Welcome to Claude Code! This is where your conversation with Claude will appear.",
      "",
      "## Quick Start:",
      "- Use `<leader>cs` to send selected text or current context to Claude",
      "- Use `<leader>cd` to send diagnostics to Claude",  
      "- Press `q` to close this window",
      "",
      "## Server Status:",
      string.format("- Port: %d", require("claude-code.server").get_server().port),
      string.format("- Status: %s", config.server_running and "Connected" or "Disconnected"),
      "",
      "---",
      ""
    }
    vim.api.nvim_buf_set_lines(state.conversation_buf, 0, -1, false, lines)
  end
  
  -- Create window using snacks.nvim
  state.conversation_win = Snacks.win({
    buf = state.conversation_buf,
    position = conv_config.position,
    width = conv_config.width,
    border = conv_config.border,
    title = "Claude Code",
    footer = "Press 'q' to close",
  })
  
  -- Set up keymaps
  vim.keymap.set("n", "q", function()
    M.close_conversation()
  end, { buffer = state.conversation_buf, nowait = true })
end

-- Close conversation window
function M.close_conversation()
  if state.conversation_win then
    pcall(vim.api.nvim_win_close, state.conversation_win, true)
    state.conversation_win = nil
  end
end

-- Send selection to Claude
---@param start_line number
---@param end_line number
function M.send_selection(start_line, end_line)
  local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
  local text = table.concat(lines, "\n")
  
  -- TODO: Send to Claude via RPC
  vim.notify("Sending selection to Claude...", vim.log.levels.INFO)
end

-- Send current context
function M.send_current()
  -- TODO: Implement context detection
  vim.notify("Sending current context to Claude...", vim.log.levels.INFO)
end

-- Show diagnostics
function M.show_diagnostics()
  local diagnostics = vim.diagnostic.get()
  
  if #diagnostics == 0 then
    vim.notify("No diagnostics found", vim.log.levels.INFO)
    return
  end
  
  -- TODO: Format and send to Claude
  vim.notify("Found " .. #diagnostics .. " diagnostics", vim.log.levels.INFO)
end

return M