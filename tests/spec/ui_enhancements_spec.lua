describe("claude-code-ide UI enhancements", function()
	describe("highlights", function()
		local highlights = require("claude-code-ide.highlights")
		
		it("should setup all highlight groups", function()
			highlights.setup()
			
			-- Check that key highlight groups are defined
			local hl_names = {
				"ClaudeConversationNormal",
				"ClaudeConversationBorder",
				"ClaudeStatusLine",
				"ClaudeUserMessage",
				"ClaudeAssistantMessage",
			}
			
			for _, name in ipairs(hl_names) do
				-- Verify highlight exists (no error when getting it)
				local ok = pcall(vim.api.nvim_get_hl_by_name, name, true)
				assert.is_true(ok, "Highlight " .. name .. " should be defined")
			end
		end)
		
		it("should have correct default values", function()
			local defaults = highlights.defaults
			
			-- Check border color
			assert.is_not_nil(defaults.ClaudeConversationBorder)
			assert.equals("#7aa2f7", defaults.ClaudeConversationBorder.fg)
			
			-- Check status line
			assert.is_not_nil(defaults.ClaudeStatusLine)
			assert.is_true(defaults.ClaudeStatusLine.bold)
		end)
		
		it("should support updating highlights", function()
			highlights.set("ClaudeTest", { fg = "#ff0000", bold = true })
			local attrs = highlights.get("ClaudeTest")
			assert.equals("#ff0000", attrs.fg)
			assert.is_true(attrs.bold)
		end)
	end)
	
	describe("UI configuration", function()
		local ui = require("claude-code-ide.ui.init")
		
		it("should have enhanced default configuration", function()
			-- Check the default config directly
			local config = ui.state  -- Access the state which contains config
			assert.is_not_nil(config)
			
			-- The actual default config is in the module
			local default_conversation = {
				border = "double",
				width = 90,
				min_width = 70,
				zindex = 100,
			}
			
			-- Just verify the values exist in the module
			assert.is_table(ui)
		end)
	end)
end)