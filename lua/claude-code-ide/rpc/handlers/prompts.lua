-- MCP prompts handler
-- Provides prompt template functionality

local log = require("claude-code-ide.log")

local M = {}

-- Storage for registered prompts
local prompts = {}

-- Register a prompt template
---@param name string Prompt name
---@param prompt table Prompt definition
function M.register_prompt(name, prompt)
	prompts[name] = {
		name = name,
		description = prompt.description,
		arguments = prompt.arguments or {},
		template = prompt.template,
		_meta = prompt._meta,
	}
	log.debug("Prompts", "Registered prompt", { name = name })
end

-- List all available prompts
---@param rpc table RPC instance
---@param params table Request parameters
---@return table Response with prompts list
function M.list_prompts(rpc, params)
	log.debug("Prompts", "list_prompts called", params)
	
	local prompt_list = {}
	for name, prompt in pairs(prompts) do
		table.insert(prompt_list, {
			name = prompt.name,
			description = prompt.description,
			arguments = prompt.arguments,
			_meta = prompt._meta,
		})
	end
	
	log.debug("Prompts", "Returning prompts list", { count = #prompt_list })
	
	return {
		prompts = prompt_list,
	}
end

-- Get and execute a prompt template
---@param rpc table RPC instance
---@param params table Request parameters with name and arguments
---@return table Response with prompt messages
function M.get_prompt(rpc, params)
	log.debug("Prompts", "get_prompt called", params)
	
	if not params or not params.name then
		error("Prompt name is required")
	end
	
	local prompt = prompts[params.name]
	if not prompt then
		error("Prompt not found: " .. params.name)
	end
	
	-- Validate arguments if schema is defined
	local args = params.arguments or {}
	for _, arg_def in ipairs(prompt.arguments or {}) do
		if arg_def.required and not args[arg_def.name] then
			error("Required argument missing: " .. arg_def.name)
		end
	end
	
	-- Process the template
	local messages = {}
	if type(prompt.template) == "function" then
		-- Execute template function
		local ok, result = pcall(prompt.template, args)
		if not ok then
			error("Failed to execute prompt template: " .. tostring(result))
		end
		messages = result
	elseif type(prompt.template) == "string" then
		-- Simple string template with variable substitution
		local text = prompt.template
		for key, value in pairs(args) do
			text = text:gsub("{{" .. key .. "}}", tostring(value))
		end
		messages = {
			{
				role = "user",
				content = {
					type = "text",
					text = text,
				},
			},
		}
	elseif type(prompt.template) == "table" then
		-- Direct message array
		messages = prompt.template
	end
	
	-- Ensure messages is an array
	if not vim.tbl_islist(messages) then
		messages = { messages }
	end
	
	return {
		description = prompt.description,
		messages = messages,
	}
end

-- Initialize with some default prompts
function M.setup()
	-- Code review prompt
	M.register_prompt("code-review", {
		description = "Review code for potential issues and improvements",
		arguments = {
			{
				name = "filePath",
				description = "Path to the file to review",
				required = true,
			},
		},
		template = function(args)
			local filepath = args.filePath
			local content = vim.fn.readfile(vim.fn.expand(filepath))
			return {
				{
					role = "user",
					content = {
						type = "text",
						text = string.format(
							"Please review the following code from %s and provide feedback on:\n" ..
							"1. Potential bugs or issues\n" ..
							"2. Code quality and best practices\n" ..
							"3. Performance considerations\n" ..
							"4. Suggested improvements\n\n" ..
							"```\n%s\n```",
							filepath,
							table.concat(content, "\n")
						),
					},
				},
			}
		end,
	})
	
	-- Explain code prompt
	M.register_prompt("explain-code", {
		description = "Explain what the selected code does",
		arguments = {
			{
				name = "code",
				description = "The code to explain",
				required = true,
			},
			{
				name = "language",
				description = "Programming language",
				required = false,
			},
		},
		template = "Please explain what the following {{language}} code does:\n\n```{{language}}\n{{code}}\n```",
	})
	
	-- Generate test prompt
	M.register_prompt("generate-tests", {
		description = "Generate unit tests for the given code",
		arguments = {
			{
				name = "code",
				description = "The code to generate tests for",
				required = true,
			},
			{
				name = "framework",
				description = "Testing framework to use",
				required = false,
			},
		},
		template = function(args)
			local framework = args.framework or "the appropriate testing framework"
			return {
				{
					role = "user",
					content = {
						type = "text",
						text = string.format(
							"Please generate comprehensive unit tests for the following code using %s:\n\n```\n%s\n```",
							framework,
							args.code
						),
					},
				},
			}
		end,
	})
end

return M