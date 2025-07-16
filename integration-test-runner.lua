#!/usr/bin/env lua

-- Integration test runner that runs tests individually
local test_files = {
	"tests/integration/server_integration_spec.lua",
	"tests/integration/tools_integration_spec.lua",
	"tests/integration/session_integration_spec.lua",
}

local results = {}
local passed = 0
local failed = 0

print("Running Integration Tests")
print("========================")
print("")

for _, file in ipairs(test_files) do
	-- Check if file exists
	local f = io.open(file, "r")
	if f then
		f:close()
		io.write(string.format("Testing %s... ", file))
		io.flush()

		-- Run the test
		local cmd = string.format(
			"nvim --headless -u tests/integration_init.lua -c \"lua require('plenary.busted').run('%s')\" -c 'qa!' 2>&1",
			file
		)

		local handle = io.popen(cmd)
		if handle then
			local output = handle:read("*a")
			local success = handle:close()

			if success and output:find("Success:") and not output:find("Failed : %[0m%s*[1-9]") then
				print("PASS")
				passed = passed + 1
			else
				print("FAIL")
				failed = failed + 1
				table.insert(results, { file = file, status = "FAILED", output = output })
			end
		else
			print("ERROR")
			failed = failed + 1
			table.insert(results, { file = file, status = "ERROR" })
		end
	else
		print(string.format("SKIP %s (not found)", file))
	end
end

print("")
print("Integration Test Summary:")
print("========================")
print(string.format("Total:  %d", passed + failed))
print(string.format("Passed: %d", passed))
print(string.format("Failed: %d", failed))

if failed > 0 then
	print("")
	print("Failed tests:")
	for _, result in ipairs(results) do
		if result.status == "FAILED" or result.status == "ERROR" then
			print("  - " .. result.file)
			if result.output and (result.output:find("Error") or result.output:find("stack traceback")) then
				-- Extract error message
				local error_line = result.output:match("([^\n]*[Ee]rror[^\n]*)")
				if error_line then
					print("    Error: " .. error_line)
				end
			end
		end
	end
end

os.exit(failed > 0 and 1 or 0)