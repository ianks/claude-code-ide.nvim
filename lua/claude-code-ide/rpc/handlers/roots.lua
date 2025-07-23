-- MCP roots/list handler
-- Provides workspace root directories information

local log = require("claude-code-ide.log")

local M = {}

-- List workspace root directories
---@param rpc table RPC instance
---@param params table Request parameters
---@return table Response with roots list
function M.list_roots(rpc, params)
	log.debug("Roots", "list_roots called", params)
	
	local roots = {}
	
	-- Get current working directory as a root
	local cwd = vim.fn.getcwd()
	table.insert(roots, {
		uri = "file://" .. cwd,
		name = vim.fn.fnamemodify(cwd, ":t"),
	})
	
	-- Check if we're in a git repository
	local git_root = vim.fn.systemlist("git rev-parse --show-toplevel")[1]
	if vim.v.shell_error == 0 and git_root and git_root ~= cwd then
		table.insert(roots, {
			uri = "file://" .. git_root,
			name = vim.fn.fnamemodify(git_root, ":t") .. " (git)",
		})
	end
	
	-- Add any additional project roots from LSP
	local clients = vim.lsp.get_active_clients()
	local seen_roots = { [cwd] = true }
	if git_root then
		seen_roots[git_root] = true
	end
	
	for _, client in ipairs(clients) do
		if client.config and client.config.root_dir then
			local root_dir = client.config.root_dir
			if not seen_roots[root_dir] then
				seen_roots[root_dir] = true
				table.insert(roots, {
					uri = "file://" .. root_dir,
					name = vim.fn.fnamemodify(root_dir, ":t") .. " (" .. client.name .. ")",
				})
			end
		end
	end
	
	log.debug("Roots", "Returning roots list", { count = #roots })
	
	return {
		roots = roots,
	}
end

return M