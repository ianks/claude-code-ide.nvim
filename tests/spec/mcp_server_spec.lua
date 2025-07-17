-- MCP Server Specification Tests
-- Declarative tests based on SPEC.md requirements

local spec = require("tests.spec.helpers.mcp_spec_dsl")

spec.describe("MCP Server", function()
	spec.server_info({
		name = "claude-code-ide.nvim",
		version = "0.1.0",
		protocol_version = "2025-06-18",
	})

	spec.discovery({
		lock_file_pattern = "~/.claude/ide/<port>.lock",
		lock_file_schema = {
			pid = "number",
			workspaceFolders = "array",
			ideName = "string",
			transport = "string",
			runningInWindows = "boolean",
			authToken = "string",
		},
		port_range = { min = 10000, max = 65535 },
	})

	spec.connection({
		transport = "websocket",
		host = "127.0.0.1",
		auth_header = "x-claude-code-ide-authorization",
		auth_type = "uuid",
	})

	spec.environment_variables({
		{ name = "ENABLE_IDE_INTEGRATION", value = "true" },
		{ name = "CLAUDE_CODE_SSE_PORT", value = "<port>" },
	})

	spec.initialization({
		request = {
			method = "initialize",
			params = {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = {
					name = "Claude CLI",
					version = "string",
				},
			},
		},
		response = {
			protocolVersion = "2025-06-18",
			capabilities = {
				tools = { listChanged = true },
				resources = { listChanged = true },
			},
			serverInfo = {
				name = "claude-code-ide.nvim",
				version = "0.1.0",
			},
			instructions = "Neovim MCP server for Claude integration",
		},
	})

	spec.tool("openFile", {
		description = "Open a file in the editor",
		input_schema = {
			filePath = { type = "string", required = true },
			preview = { type = "boolean", default = false },
			startText = { type = "string" },
			endText = { type = "string" },
			makeFrontmost = { type = "boolean", default = true },
		},
		response_format = "content",
		implementation_notes = {
			"Use vim.cmd('e ' .. filePath) to open files",
			"Use vim.fn.searchpos() for text selection",
			"Focus buffer with vim.api.nvim_set_current_win() if makeFrontmost",
		},
	})

	spec.tool("openDiff", {
		description = "Open a diff view",
		input_schema = {
			old_file_path = { type = "string", required = true },
			new_file_path = { type = "string", required = true },
			new_file_contents = { type = "string", required = true },
			tab_name = { type = "string", required = true },
		},
		response_format = "content",
		response_states = { "FILE_SAVED", "DIFF_REJECTED" },
		implementation_notes = {
			"Create scratch buffers with nvim_create_buf",
			"Use diffsplit for diff view",
			"Listen for BufWritePost to detect save",
			"Detect tab close for rejection",
		},
	})

	spec.tool("getDiagnostics", {
		description = "Get language diagnostics",
		input_schema = {
			uri = { type = "string", description = "Optional file URI" },
		},
		response_format = "json",
		response_schema = {
			type = "array",
			items = {
				uri = "string",
				diagnostics = {
					type = "array",
					items = {
						message = "string",
						severity = { enum = { "Error", "Warning", "Information", "Hint" } },
						range = {
							start = { line = "number", character = "number" },
							["end"] = { line = "number", character = "number" },
						},
					},
				},
			},
		},
		implementation_notes = {
			"Use vim.diagnostic.get() to retrieve diagnostics",
			"Map severity numbers to strings (1=Error, 2=Warning, etc.)",
		},
	})

	spec.tool("getCurrentSelection", {
		description = "Get current text selection",
		input_schema = {},
		response_format = "json",
		response_schema = {
			success = "boolean",
			text = "string",
			filePath = "string",
			selection = {
				start = { line = "number", character = "number" },
				["end"] = { line = "number", character = "number" },
			},
		},
		implementation_notes = {
			'Use vim.fn.getpos("\'<") and vim.fn.getpos("\'>") for selection',
			"Extract text with vim.api.nvim_buf_get_text",
		},
	})

	spec.tool("getOpenEditors", {
		description = "Get open editors",
		input_schema = {},
		response_format = "json",
		response_schema = {
			type = "array",
			items = {
				filePath = "string",
				active = "boolean",
				dirty = "boolean",
			},
		},
		implementation_notes = {
			"Use vim.api.nvim_list_bufs() to get buffers",
			"Check vim.bo[bufnr].modified for dirty state",
		},
	})

	spec.tool("getWorkspaceFolders", {
		description = "Get workspace folders",
		input_schema = {},
		response_format = "json",
		response_schema = {
			type = "array",
			items = "string",
		},
		implementation_notes = {
			"Return vim.fn.getcwd() as single workspace",
			"Could extend with project.nvim integration",
		},
	})

	spec.security({
		lock_file_permissions = "600",
		bind_address = "127.0.0.1",
		auth_required = true,
		path_validation = true,
	})

	spec.response_format({
		type = "content",
		schema = {
			content = {
				type = "array",
				items = {
					type = { enum = { "text" } },
					text = "string",
				},
			},
		},
	})
end)
