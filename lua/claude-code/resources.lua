-- MCP Resources implementation for claude-code.nvim
-- Provides access to files, templates, and other resources via MCP protocol

local notify = require("claude-code.ui.notify")
local log = require("claude-code.log")
local events = require("claude-code.events")
local config = require("claude-code.config")

local M = {}

-- Resource registry
local resources = {}

-- Resource types
M.types = {
	FILE = "file",
	TEMPLATE = "template",
	SNIPPET = "snippet",
	DOCUMENTATION = "documentation",
	WORKSPACE = "workspace",
}

-- Register a resource
---@param uri string Resource URI (e.g., "file:///path/to/file")
---@param name string Human-readable name
---@param description string? Resource description
---@param mime_type string? MIME type of the resource
---@param metadata table? Additional metadata
function M.register(uri, name, description, mime_type, metadata)
	resources[uri] = {
		uri = uri,
		name = name,
		description = description,
		mimeType = mime_type,
		metadata = metadata or {},
	}

	log.debug("RESOURCES", "Registered resource", {
		uri = uri,
		name = name,
		mime_type = mime_type,
	})
end

-- Unregister a resource
---@param uri string Resource URI
function M.unregister(uri)
	resources[uri] = nil
end

-- List all resources
---@param filter? table Filter criteria (type, pattern, etc.)
---@return table[] Array of resource definitions
function M.list(filter)
	filter = filter or {}
	local list = {}

	for uri, resource in pairs(resources) do
		local include = true

		-- Apply filters
		if filter.type then
			local resource_type = M.get_type(uri)
			if resource_type ~= filter.type then
				include = false
			end
		end

		if filter.pattern and include then
			if not uri:match(filter.pattern) and not resource.name:match(filter.pattern) then
				include = false
			end
		end

		if include then
			table.insert(list, {
				uri = resource.uri,
				name = resource.name,
				description = resource.description,
				mimeType = resource.mimeType,
				metadata = resource.metadata,
			})
		end
	end

	return list
end

-- Get resource type from URI
---@param uri string Resource URI
---@return string? Resource type
function M.get_type(uri)
	if uri:match("^file://") then
		return M.types.FILE
	elseif uri:match("^template://") then
		return M.types.TEMPLATE
	elseif uri:match("^snippet://") then
		return M.types.SNIPPET
	elseif uri:match("^doc://") or uri:match("^documentation://") then
		return M.types.DOCUMENTATION
	elseif uri:match("^workspace://") then
		return M.types.WORKSPACE
	end
	return nil
end

-- Read resource content
---@param uri string Resource URI
---@return table? Resource content response
function M.read(uri)
	local resource = resources[uri]
	if not resource then
		-- Try to handle dynamic resources
		return M._read_dynamic(uri)
	end

	-- Read based on resource type
	local resource_type = M.get_type(uri)

	if resource_type == M.types.FILE then
		return M._read_file(uri)
	elseif resource_type == M.types.TEMPLATE then
		return M._read_template(uri)
	elseif resource_type == M.types.SNIPPET then
		return M._read_snippet(uri)
	elseif resource_type == M.types.DOCUMENTATION then
		return M._read_documentation(uri)
	elseif resource_type == M.types.WORKSPACE then
		return M._read_workspace(uri)
	else
		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/plain",
					text = "Unknown resource type",
				},
			},
		}
	end
end

-- Read file resource
function M._read_file(uri)
	local path = uri:gsub("^file://", "")

	-- Check if file exists
	if vim.fn.filereadable(path) ~= 1 then
		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/plain",
					text = "File not found: " .. path,
				},
			},
		}
	end

	-- Read file content
	local lines = vim.fn.readfile(path)
	local content = table.concat(lines, "\n")

	-- Detect MIME type
	local mime_type = M._detect_mime_type(path)

	-- Handle binary files
	if M._is_binary(mime_type) then
		return {
			contents = {
				{
					uri = uri,
					mimeType = mime_type,
					blob = vim.base64.encode(content),
				},
			},
		}
	end

	return {
		contents = {
			{
				uri = uri,
				mimeType = mime_type,
				text = content,
			},
		},
	}
end

-- Read template resource
function M._read_template(uri)
	local template_name = uri:gsub("^template://", "")
	local template_dir = vim.fn.stdpath("config") .. "/claude-templates"
	local template_path = template_dir .. "/" .. template_name

	if vim.fn.filereadable(template_path) ~= 1 then
		-- Try built-in templates
		local builtin = M._get_builtin_template(template_name)
		if builtin then
			return {
				contents = {
					{
						uri = uri,
						mimeType = "text/plain",
						text = builtin,
					},
				},
			}
		end

		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/plain",
					text = "Template not found: " .. template_name,
				},
			},
		}
	end

	local content = table.concat(vim.fn.readfile(template_path), "\n")

	return {
		contents = {
			{
				uri = uri,
				mimeType = "text/plain",
				text = content,
			},
		},
	}
end

-- Read snippet resource
function M._read_snippet(uri)
	local snippet_name = uri:gsub("^snippet://", "")

	-- Try to find snippet in various sources
	-- 1. User snippets
	local user_snippets = M._get_user_snippet(snippet_name)
	if user_snippets then
		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/plain",
					text = user_snippets,
				},
			},
		}
	end

	-- 2. Built-in snippets
	local builtin = M._get_builtin_snippet(snippet_name)
	if builtin then
		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/plain",
					text = builtin,
				},
			},
		}
	end

	return {
		contents = {
			{
				uri = uri,
				mimeType = "text/plain",
				text = "Snippet not found: " .. snippet_name,
			},
		},
	}
end

-- Read documentation resource
function M._read_documentation(uri)
	local doc_path = uri:gsub("^doc://", ""):gsub("^documentation://", "")

	-- Check if it's a help topic
	if doc_path:match("^help/") then
		local help_topic = doc_path:gsub("^help/", "")
		local help_content = M._get_help_content(help_topic)

		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/plain",
					text = help_content or "Help topic not found: " .. help_topic,
				},
			},
		}
	end

	-- Check for project documentation
	local doc_file = vim.fn.getcwd() .. "/docs/" .. doc_path
	if vim.fn.filereadable(doc_file) == 1 then
		local content = table.concat(vim.fn.readfile(doc_file), "\n")
		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/markdown",
					text = content,
				},
			},
		}
	end

	return {
		contents = {
			{
				uri = uri,
				mimeType = "text/plain",
				text = "Documentation not found: " .. doc_path,
			},
		},
	}
end

-- Read workspace resource
function M._read_workspace(uri)
	local workspace_info = uri:gsub("^workspace://", "")

	if workspace_info == "info" then
		-- Return workspace information
		local info = {
			root = vim.fn.getcwd(),
			name = vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
			files = vim.fn.systemlist("find . -type f -name '*.lua' -o -name '*.vim' | head -20"),
			git_branch = vim.fn.system("git branch --show-current 2>/dev/null"):gsub("\n", ""),
		}

		return {
			contents = {
				{
					uri = uri,
					mimeType = "application/json",
					text = vim.json.encode(info),
				},
			},
		}
	elseif workspace_info == "structure" then
		-- Return project structure
		local tree = vim.fn.system("tree -L 3 -I 'node_modules|.git' 2>/dev/null")
		if vim.v.shell_error ~= 0 then
			tree = vim.fn.system(
				"find . -type d -name node_modules -prune -o -type d -name .git -prune -o -type f -print | head -50"
			)
		end

		return {
			contents = {
				{
					uri = uri,
					mimeType = "text/plain",
					text = tree,
				},
			},
		}
	end

	return {
		contents = {
			{
				uri = uri,
				mimeType = "text/plain",
				text = "Unknown workspace resource: " .. workspace_info,
			},
		},
	}
end

-- Handle dynamic resources
function M._read_dynamic(uri)
	-- Check if it's a file URI
	if uri:match("^file://") then
		-- Register it dynamically
		local path = uri:gsub("^file://", "")
		local name = vim.fn.fnamemodify(path, ":t")
		M.register(uri, name, "File: " .. path, M._detect_mime_type(path))

		-- Read it
		return M._read_file(uri)
	end

	return nil
end

-- Detect MIME type from file path
function M._detect_mime_type(path)
	local ext = vim.fn.fnamemodify(path, ":e"):lower()

	local mime_types = {
		-- Text
		txt = "text/plain",
		md = "text/markdown",
		markdown = "text/markdown",
		rst = "text/x-rst",
		tex = "text/x-tex",

		-- Code
		lua = "text/x-lua",
		vim = "text/x-vim",
		py = "text/x-python",
		js = "text/javascript",
		ts = "text/typescript",
		jsx = "text/jsx",
		tsx = "text/tsx",
		java = "text/x-java",
		c = "text/x-c",
		cpp = "text/x-c++",
		h = "text/x-c",
		hpp = "text/x-c++",
		cs = "text/x-csharp",
		go = "text/x-go",
		rs = "text/x-rust",
		rb = "text/x-ruby",
		php = "text/x-php",
		sh = "text/x-sh",
		bash = "text/x-sh",
		zsh = "text/x-sh",
		fish = "text/x-sh",

		-- Data
		json = "application/json",
		yaml = "text/yaml",
		yml = "text/yaml",
		toml = "text/toml",
		xml = "text/xml",
		csv = "text/csv",

		-- Web
		html = "text/html",
		css = "text/css",
		scss = "text/x-scss",
		sass = "text/x-sass",
		less = "text/x-less",

		-- Images
		png = "image/png",
		jpg = "image/jpeg",
		jpeg = "image/jpeg",
		gif = "image/gif",
		svg = "image/svg+xml",
		webp = "image/webp",

		-- Documents
		pdf = "application/pdf",
		doc = "application/msword",
		docx = "application/vnd.openxmlformats-officedocument.wordprocessingml.document",

		-- Archives
		zip = "application/zip",
		tar = "application/x-tar",
		gz = "application/gzip",
		["7z"] = "application/x-7z-compressed",
		rar = "application/x-rar-compressed",
	}

	return mime_types[ext] or "text/plain"
end

-- Check if MIME type is binary
function M._is_binary(mime_type)
	-- Images are always binary
	if mime_type:match("^image/") then
		return true
	end

	-- Application types are binary except for text-based formats
	if mime_type:match("^application/") then
		-- Text-based application formats
		if mime_type:match("json$") or mime_type:match("xml$") then
			return false
		end
		return true
	end

	-- Everything else (text/*, etc.) is not binary
	return false
end

-- Get built-in template
function M._get_builtin_template(name)
	local templates = {
		["bug-report"] = [[
## Bug Report

**Description:**
[Clear description of the bug]

**Steps to Reproduce:**
1. [First step]
2. [Second step]
3. [...]

**Expected Behavior:**
[What should happen]

**Actual Behavior:**
[What actually happens]

**Environment:**
- OS: [e.g., macOS 13.0]
- Neovim version: [e.g., 0.9.0]
- Plugin version: [e.g., 1.0.0]

**Additional Context:**
[Any other relevant information]
]],
		["feature-request"] = [[
## Feature Request

**Problem:**
[Description of the problem this feature would solve]

**Proposed Solution:**
[Your idea for how to solve it]

**Alternatives Considered:**
[Other solutions you've thought about]

**Additional Context:**
[Any other relevant information]
]],
		["code-review"] = [[
## Code Review

**Summary:**
[Brief summary of the changes]

**Changes:**
- [ ] [Change 1]
- [ ] [Change 2]
- [ ] [...]

**Testing:**
- [ ] Unit tests added/updated
- [ ] Manual testing completed
- [ ] Documentation updated

**Questions/Concerns:**
[Any specific areas that need attention]
]],
	}

	return templates[name]
end

-- Get built-in snippet
function M._get_builtin_snippet(name)
	local snippets = {
		["error-handler"] = [[
local ok, result = pcall(function()
	-- Your code here
end)

if not ok then
	-- Handle error
	vim.notify("Error: " .. tostring(result), vim.log.levels.ERROR)
	return nil
end
]],
		["async-function"] = [[
local async = require("plenary.async")

local my_async_function = async.void(function()
	-- Async code here
	local result = async.util.scheduler()
	
	-- More async operations
end)
]],
		["test-case"] = [[
describe("Component Name", function()
	before_each(function()
		-- Setup
	end)
	
	after_each(function()
		-- Cleanup
	end)
	
	it("should do something", function()
		-- Test code
		assert.equals(expected, actual)
	end)
end)
]],
	}

	return snippets[name]
end

-- Get user snippet
function M._get_user_snippet(name)
	local snippet_file = vim.fn.stdpath("config") .. "/claude-snippets/" .. name .. ".snippet"
	if vim.fn.filereadable(snippet_file) == 1 then
		return table.concat(vim.fn.readfile(snippet_file), "\n")
	end
	return nil
end

-- Get help content
function M._get_help_content(topic)
	-- Capture help content
	local lines = {}

	local ok = pcall(function()
		vim.cmd("help " .. topic)
		local bufnr = vim.api.nvim_get_current_buf()
		lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.cmd("bdelete")
	end)

	if ok and #lines > 0 then
		return table.concat(lines, "\n")
	end

	return nil
end

-- Auto-register common resources on startup
function M.setup()
	-- Register current file
	vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost" }, {
		group = vim.api.nvim_create_augroup("ClaudeCodeResources", { clear = true }),
		callback = function(args)
			local bufnr = args.buf
			local filepath = vim.api.nvim_buf_get_name(bufnr)

			if filepath ~= "" then
				local uri = "file://" .. filepath
				local name = vim.fn.fnamemodify(filepath, ":t")
				local ft = vim.bo[bufnr].filetype

				M.register(uri, name, "Current file", M._detect_mime_type(filepath), {
					filetype = ft,
					modified = vim.bo[bufnr].modified,
				})
			end
		end,
	})

	-- Register workspace resources
	M.register("workspace://info", "Workspace Info", "Current workspace information")
	M.register("workspace://structure", "Project Structure", "Project directory structure")

	-- Register common templates
	M.register("template://bug-report", "Bug Report Template", "Template for reporting bugs")
	M.register("template://feature-request", "Feature Request Template", "Template for requesting features")
	M.register("template://code-review", "Code Review Template", "Template for code reviews")

	-- Register useful snippets
	M.register("snippet://error-handler", "Error Handler", "Lua error handling pattern")
	M.register("snippet://async-function", "Async Function", "Plenary async function template")
	M.register("snippet://test-case", "Test Case", "Busted test case template")

	log.debug("RESOURCES", "Resources system initialized")
end

return M
