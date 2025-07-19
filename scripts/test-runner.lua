#!/usr/bin/env luajit

-- Test runner that runs tests individually to avoid hanging issues
local test_files = {}
local results = {}

-- Load ignored tests
local ignored_tests = {}
local function load_ignored_tests()
	local f = io.open(".testignore", "r")
	if f then
		for line in f:lines() do
			if line:match("^[^#]") and line:match("%S") then
				ignored_tests[line:gsub("^%s+", ""):gsub("%s+$", "")] = true
			end
		end
		f:close()
	end
end

-- Find all test files
local function find_test_files()
	load_ignored_tests()
	local handle = io.popen("find tests/spec -name '*_spec.lua' -type f | sort")
	if handle then
		for file in handle:lines() do
			if not ignored_tests[file] then
				table.insert(test_files, file)
			end
		end
		handle:close()
	end
end

-- Run a single test file
local function run_test(file)
	io.write(string.format("Testing %s... ", file))
	io.flush()

	local cmd = string.format(
		"nvim --headless -u tests/minimal_init.lua -c \"lua require('plenary.busted').run('%s')\" -c 'qa!' 2>&1",
		file
	)

	local handle = io.popen(cmd)
	if handle then
		local output = handle:read("*a")
		local success = handle:close()

		if
			success
			and output:find("Success:")
			and not output:find("Failed : %[0m%s*[1-9]")
			and not output:find("Errors : %[0m%s*[1-9]")
		then
			print("PASS")
			return true
		else
			print("FAIL")
			if output:find("Error") or output:find("Fail") then
				print("  Output:", output:match("([^\n]*[Ee]rror[^\n]*)") or output:match("([^\n]*[Ff]ail[^\n]*)"))
			end
			return false
		end
	end

	print("ERROR")
	return false
end

-- Main
find_test_files()

print("Running " .. #test_files .. " test files...")
print("")

local passed = 0
local failed = 0

for _, file in ipairs(test_files) do
	if run_test(file) then
		passed = passed + 1
	else
		failed = failed + 1
		table.insert(results, { file = file, status = "FAILED" })
	end
end

print("")
print("Summary:")
print("========")
print(string.format("Total:  %d", passed + failed))
print(string.format("Passed: %d", passed))
print(string.format("Failed: %d", failed))

if failed > 0 then
	print("")
	print("Failed tests:")
	for _, result in ipairs(results) do
		if result.status == "FAILED" then
			print("  - " .. result.file)
		end
	end
end

-- Exit with appropriate code
os.exit(failed > 0 and 1 or 0)
