-- Tests for MCP resources implementation

local resources = require("claude-code.resources")

describe("MCP Resources", function()
	before_each(function()
		-- Clear all resources
		for _, resource in ipairs(resources.list()) do
			resources.unregister(resource.uri)
		end
	end)

	describe("Resource Registration", function()
		it("should register a resource", function()
			resources.register("file:///test.lua", "Test File", "A test file", "text/x-lua")

			local list = resources.list()
			assert.equals(1, #list)
			assert.equals("file:///test.lua", list[1].uri)
			assert.equals("Test File", list[1].name)
			assert.equals("A test file", list[1].description)
			assert.equals("text/x-lua", list[1].mimeType)
		end)

		it("should unregister a resource", function()
			resources.register("file:///test.lua", "Test File")
			resources.unregister("file:///test.lua")

			local list = resources.list()
			assert.equals(0, #list)
		end)

		it("should register with metadata", function()
			resources.register("file:///test.lua", "Test File", nil, nil, {
				author = "Test Author",
				version = "1.0.0",
			})

			local list = resources.list()
			assert.equals("Test Author", list[1].metadata.author)
			assert.equals("1.0.0", list[1].metadata.version)
		end)
	end)

	describe("Resource Listing", function()
		before_each(function()
			resources.register("file:///test1.lua", "Test 1", nil, "text/x-lua")
			resources.register("file:///test2.py", "Test 2", nil, "text/x-python")
			resources.register("template://bug-report", "Bug Report", nil, "text/plain")
			resources.register("snippet://test", "Test Snippet", nil, "text/plain")
		end)

		it("should list all resources", function()
			local list = resources.list()
			assert.equals(4, #list)
		end)

		it("should filter by type", function()
			local list = resources.list({ type = resources.types.FILE })
			assert.equals(2, #list)

			list = resources.list({ type = resources.types.TEMPLATE })
			assert.equals(1, #list)
			assert.equals("template://bug-report", list[1].uri)
		end)

		it("should filter by pattern", function()
			local list = resources.list({ pattern = "test1" })
			assert.equals(1, #list)
			assert.equals("file:///test1.lua", list[1].uri)

			-- Pattern can match name too
			list = resources.list({ pattern = "Bug" })
			assert.equals(1, #list)
			assert.equals("template://bug-report", list[1].uri)
		end)
	end)

	describe("Resource Type Detection", function()
		it("should detect file type", function()
			assert.equals(resources.types.FILE, resources.get_type("file:///test.lua"))
			assert.equals(resources.types.FILE, resources.get_type("file:///path/to/file.txt"))
		end)

		it("should detect template type", function()
			assert.equals(resources.types.TEMPLATE, resources.get_type("template://bug-report"))
		end)

		it("should detect snippet type", function()
			assert.equals(resources.types.SNIPPET, resources.get_type("snippet://error-handler"))
		end)

		it("should detect documentation type", function()
			assert.equals(resources.types.DOCUMENTATION, resources.get_type("doc://readme"))
			assert.equals(resources.types.DOCUMENTATION, resources.get_type("documentation://api/functions"))
		end)

		it("should detect workspace type", function()
			assert.equals(resources.types.WORKSPACE, resources.get_type("workspace://info"))
		end)

		it("should return nil for unknown types", function()
			assert.is_nil(resources.get_type("unknown://resource"))
		end)
	end)

	describe("File Resources", function()
		it("should read existing file", function()
			-- Create a temp file
			local temp_file = vim.fn.tempname()
			local file = io.open(temp_file, "w")
			file:write("Hello, World!")
			file:close()

			local result = resources.read("file://" .. temp_file)

			assert.truthy(result)
			assert.equals(1, #result.contents)
			assert.equals("file://" .. temp_file, result.contents[1].uri)
			assert.equals("Hello, World!", result.contents[1].text)
			assert.truthy(result.contents[1].mimeType)

			-- Cleanup
			vim.fn.delete(temp_file)
		end)

		it("should handle non-existent file", function()
			local result = resources.read("file:///non/existent/file.txt")

			assert.truthy(result)
			assert.equals(1, #result.contents)
			assert.truthy(result.contents[1].text:match("File not found"))
		end)

		it("should detect MIME types correctly", function()
			local mime = resources._detect_mime_type

			assert.equals("text/x-lua", mime("test.lua"))
			assert.equals("text/x-python", mime("test.py"))
			assert.equals("text/javascript", mime("test.js"))
			assert.equals("text/markdown", mime("README.md"))
			assert.equals("application/json", mime("config.json"))
			assert.equals("image/png", mime("image.png"))
			assert.equals("text/plain", mime("unknown.xyz"))
		end)

		it("should handle binary files", function()
			-- Mock base64 encoding
			vim.base64 = vim.base64 or {}
			vim.base64.encode = function(data)
				return "base64data"
			end

			-- Test the actual _is_binary function output
			local is_binary = resources._is_binary
			assert.equals(true, is_binary("image/png"))
			assert.equals(true, is_binary("application/pdf"))
			assert.equals(false, is_binary("text/plain"))
			assert.equals(false, is_binary("application/json"))
		end)
	end)

	describe("Template Resources", function()
		it("should read built-in template", function()
			-- First register the template
			resources.register("template://bug-report", "Bug Report", "Template for bug reports", "text/plain")

			local result = resources.read("template://bug-report")

			assert.truthy(result)
			assert.equals(1, #result.contents)
			assert.truthy(result.contents[1].text:match("Bug Report"))
			assert.truthy(result.contents[1].text:match("Description"))
		end)

		it("should handle non-existent template", function()
			-- Register a template that doesn't have built-in content
			resources.register("template://non-existent", "Non-existent", "Does not exist", "text/plain")

			local result = resources.read("template://non-existent")

			assert.truthy(result)
			assert.truthy(result.contents[1].text:match("Template not found"))
		end)

		it("should have built-in templates", function()
			local bug_report = resources._get_builtin_template("bug-report")
			local feature_request = resources._get_builtin_template("feature-request")
			local code_review = resources._get_builtin_template("code-review")

			assert.truthy(bug_report)
			assert.truthy(feature_request)
			assert.truthy(code_review)
		end)
	end)

	describe("Snippet Resources", function()
		it("should read built-in snippet", function()
			-- First register the snippet
			resources.register("snippet://error-handler", "Error Handler", "Error handling pattern", "text/plain")

			local result = resources.read("snippet://error-handler")

			assert.truthy(result)
			assert.equals(1, #result.contents)
			assert.truthy(result.contents[1].text:match("pcall"))
		end)

		it("should have built-in snippets", function()
			local error_handler = resources._get_builtin_snippet("error-handler")
			local async_func = resources._get_builtin_snippet("async-function")
			local test_case = resources._get_builtin_snippet("test-case")

			assert.truthy(error_handler)
			assert.truthy(async_func)
			assert.truthy(test_case)
		end)
	end)

	describe("Workspace Resources", function()
		it("should read workspace info", function()
			-- Register the workspace resource
			resources.register("workspace://info", "Workspace Info", "Current workspace information")

			-- Mock system commands
			vim.fn.systemlist = function()
				return { "file1.lua", "file2.lua" }
			end
			vim.fn.system = function()
				return "main\n"
			end

			local result = resources.read("workspace://info")

			assert.truthy(result)
			assert.equals("application/json", result.contents[1].mimeType)

			local info = vim.json.decode(result.contents[1].text)
			assert.truthy(info.root)
			assert.truthy(info.name)
			assert.truthy(info.files)
			assert.equals("main", info.git_branch)
		end)

		it("should read workspace structure", function()
			-- Register the workspace resource
			resources.register("workspace://structure", "Project Structure", "Project directory structure")

			-- Mock tree command
			vim.fn.system = function(cmd)
				if cmd:match("tree") then
					return ".\n├── lua\n│   └── module.lua\n└── tests\n"
				end
				return ""
			end

			-- Mock shell_error with metatable
			local original_v = vim.v or {}
			vim.v = setmetatable({}, {
				__index = function(_, key)
					if key == "shell_error" then
						return 0
					end
					return original_v[key]
				end,
				__newindex = function(_, key, value)
					if key ~= "shell_error" then
						original_v[key] = value
					end
				end,
			})

			local result = resources.read("workspace://structure")

			assert.truthy(result)
			assert.truthy(result.contents[1].text:match("lua"))

			-- Restore vim.v
			vim.v = original_v
		end)
	end)

	describe("Documentation Resources", function()
		it("should handle help topics", function()
			-- Register the doc resource
			resources.register("doc://help/lua", "Lua Help", "Lua help documentation")

			-- Mock help command
			local original_cmd = vim.cmd
			vim.cmd = function(cmd)
				if cmd:match("^help ") then
					-- Simulate help buffer
					return
				elseif cmd == "bdelete" then
					return
				end
				original_cmd(cmd)
			end

			-- Mock buffer content
			vim.api.nvim_get_current_buf = function()
				return 1
			end
			vim.api.nvim_buf_get_lines = function()
				return { "*lua.txt*  Lua reference manual", "", "INTRODUCTION" }
			end

			local result = resources.read("doc://help/lua")

			assert.truthy(result)

			-- Restore
			vim.cmd = original_cmd
		end)

		it("should read project documentation", function()
			-- Register the doc resource
			resources.register("doc://README.md", "README", "Project documentation")

			-- Mock file existence
			vim.fn.filereadable = function(path)
				return path:match("docs/README.md") and 1 or 0
			end

			-- Mock file reading
			vim.fn.readfile = function()
				return { "# Project Documentation", "", "This is the readme." }
			end

			local result = resources.read("doc://README.md")

			assert.truthy(result)
			assert.equals("text/markdown", result.contents[1].mimeType)
			assert.truthy(result.contents[1].text:match("Project Documentation"))
		end)
	end)

	describe("Dynamic Resources", function()
		it("should handle unregistered file URIs", function()
			-- Create a temp file
			local temp_file = vim.fn.tempname()
			local file = io.open(temp_file, "w")
			if not file then
				error("Failed to create temp file: " .. temp_file)
			end
			file:write("Dynamic content")
			file:close()

			-- Mock filereadable to ensure it returns 1 for our temp file
			local original_filereadable = vim.fn.filereadable
			vim.fn.filereadable = function(path)
				if path == temp_file then
					return 1
				end
				return original_filereadable(path)
			end

			-- Mock readfile to return our content
			local original_readfile = vim.fn.readfile
			vim.fn.readfile = function(path)
				if path == temp_file then
					return { "Dynamic content" }
				end
				return original_readfile(path)
			end

			-- Read without registering first
			local result = resources.read("file://" .. temp_file)

			assert.truthy(result)
			assert.equals("Dynamic content", result.contents[1].text)

			-- Should now be registered
			local list = resources.list({ pattern = vim.fn.fnamemodify(temp_file, ":t") })
			assert.equals(1, #list)

			-- Restore mocks
			vim.fn.filereadable = original_filereadable
			vim.fn.readfile = original_readfile

			-- Cleanup
			vim.fn.delete(temp_file)
		end)
	end)

	describe("Resource Setup", function()
		it("should auto-register common resources", function()
			-- Clear and setup
			for _, resource in ipairs(resources.list()) do
				resources.unregister(resource.uri)
			end

			resources.setup()

			local list = resources.list()
			local uris = {}
			for _, resource in ipairs(list) do
				uris[resource.uri] = true
			end

			-- Check common resources are registered
			assert.truthy(uris["workspace://info"])
			assert.truthy(uris["workspace://structure"])
			assert.truthy(uris["template://bug-report"])
			assert.truthy(uris["snippet://error-handler"])
		end)
	end)
end)
