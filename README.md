# claude-code-ide.nvim

> **native** Claude AI integration for Neovim

🚧 **UNDER CONSTRUCTION** - This plugin is in active development. Breaking changes expected.

ai can use your editor like you do.

## what

claude-code-ide.nvim integrates Claude Code's built-in IDE features directly into Neovim via MCP. Claude can see your code, run diagnostics, open files, and help you write software without context switching.

no browser tabs. just neovim.

## features

- **websocket mcp server** - runs inside neovim, no external processes
- **ide tools** - Claude can open files, create diffs, run diagnostics
- **resource exposure** - share files, templates, workspace info
- **smart caching** - reduces api calls, improves response time
- **async everything** - non-blocking ui, background operations
- **lock file discovery** - automatic connection via `~/.claude/ide/*.lock`

## install

```lua
-- lazy.nvim
{
  "ianks/claude-code-ide.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = true,
}
```

## quickstart

```bash
# in neovim
:lua require("claude-code-ide").start()

# in terminal
claude --ide
```

that's it. Claude connects automatically.

## keymaps

| key | what |
|-----|------|
| `<leader>cc` | toggle chat |
| `<leader>cs` | send selection |
| `<leader>cd` | send diagnostics |
| `<leader>cp` | command palette |

## tools

Claude can use these to interact with your editor:

- `openFile` - open files, jump to lines
- `openDiff` - show code changes
- `getDiagnostics` - get lsp errors
- `getCurrentSelection` - read selected text
- `getOpenEditors` - list open buffers
- `getWorkspaceFolders` - get project info

## config

```lua
require("claude-code-ide").setup({
  port = 0,  -- random port
  host = "127.0.0.1",
  debug = false,
  lock_file_dir = vim.fn.expand("~/.claude/ide"),
})
```

## architecture

```
claude cli <--> websocket <--> neovim mcp server
                                   |
                                   +--> tools
                                   +--> resources
                                   +--> ui
```

## dev

```bash
just test        # run tests
just test-file   # test specific file
```

## philosophy

ai should interact with editors the way developers do. no special apis. no complex abstractions. just tools that manipulate buffers and windows.

## license

MIT