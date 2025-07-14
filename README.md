# claude-code.nvim

Neovim integration for Claude AI, enabling seamless interaction with Claude directly from your editor.

## 🚧 Status

This project is currently in early development. The directory structure and core module stubs have been created, but the WebSocket server implementation is not yet complete.

## 📁 Project Structure

```
claude-code.nvim/
├── lua/claude-code/         # Main plugin code
│   ├── server/             # WebSocket server implementation
│   ├── rpc/               # JSON-RPC protocol handlers
│   ├── ui/                # User interface (using snacks.nvim)
│   ├── api/               # Public API and commands
│   └── utils/             # Utility functions
├── plugin/                # Vim plugin entry point
├── tests/                 # Test suite (plenary.busted)
└── doc/                   # Vim help documentation
```

## 🔧 Development

### Prerequisites

- Neovim ≥ 0.8.0
- plenary.nvim
- snacks.nvim
- nvim-nio

### Running Tests

```bash
./scripts/test.sh
```

### Architecture

The plugin implements a WebSocket server that communicates with the Claude CLI using JSON-RPC 2.0 protocol. Key components:

1. **WebSocket Server**: Handles connections from Claude CLI
2. **RPC Dispatcher**: Routes JSON-RPC methods to appropriate handlers
3. **Lock File Discovery**: Allows Claude CLI to discover the running server
4. **UI Components**: Conversation windows and notifications

## 📚 Documentation

- `SPEC.md` - Technical specification for the WebSocket server
- `PLUGIN_GUIDE.md` - Comprehensive Neovim plugin development guide
- `CLAUDE.md` - Guidance for Claude Code when working with this repository

## 🤝 Contributing

This project is in early development. Contributions are welcome! Please read the specification documents before contributing.

## 📄 License

[License information to be added]