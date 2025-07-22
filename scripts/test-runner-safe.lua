#!/usr/bin/env lua

-- Safe test runner that prevents hanging tests

local function run_test_file(file)
	local cmd = string.format(
		"timeout 30s nvim --headless -u tests/minimal_init.lua -c \"lua require('plenary.busted').run('%s')\" -c \"qa!\"",
		file
	)

	print("Running test file: " .. file)
	local handle = io.popen(cmd)
	local result = handle:read("*a")
	local success = handle:close()

	print(result)
	return success
end

local function main()
	print("Starting safe test runner...")

	-- Test files to run
	local test_files = {
		"tests/spec/config_spec.lua",
		"tests/spec/events_spec.lua",
		"tests/spec/cache_spec.lua",
		"tests/spec/init_spec.lua",
	}

	local failed_tests = {}
	local passed_count = 0

	for _, test_file in ipairs(test_files) do
		local success = run_test_file(test_file)
		if success then
			passed_count = passed_count + 1
			print("✓ PASSED: " .. test_file)
		else
			table.insert(failed_tests, test_file)
			print("✗ FAILED: " .. test_file)
		end
		print("") -- Add spacing
	end

	print(string.format("Test Summary: %d/%d passed", passed_count, #test_files))

	if #failed_tests > 0 then
		print("Failed tests:")
		for _, test in ipairs(failed_tests) do
			print("  - " .. test)
		end
		os.exit(1)
	else
		print("All tests passed!")
		os.exit(0)
	end
end

main()
