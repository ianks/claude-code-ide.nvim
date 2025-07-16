-- Luacheck configuration for claude-code.nvim

-- Neovim globals
read_globals = {
    "vim",
}

-- Plugin globals
globals = {
    "_G",
    "package",
}

-- Ignore line length warnings
max_line_length = false

-- Ignore warnings about unused arguments
unused_args = false

-- Allow unused loop variables like _
unused_secondaries = false

-- Module return warning
ignore = {
    "111", -- Setting an undefined global variable
    "112", -- Mutating an undefined global variable
    "113", -- Accessing an undefined global variable
    "211", -- Unused local variable
    "212", -- Unused argument
    "213", -- Unused loop variable
    "214", -- Used variable with unused hint ("_" prefix)
    "221", -- Variable is never set
    "231", -- Variable is never accessed
    "232", -- Argument is never accessed
    "233", -- Loop variable is never accessed
    "241", -- Local variable is mutated but never accessed
    "242", -- Argument is mutated but never accessed
    "251", -- Unreachable code
    "311", -- Value assigned to a local variable is unused
    "312", -- Value of an argument is unused
    "313", -- Value of a loop variable is unused
    "314", -- Value of a field in a table literal is unused
    "411", -- Redefining a local variable
    "412", -- Redefining an argument
    "413", -- Redefining a loop variable
    "421", -- Shadowing a local variable
    "422", -- Shadowing an argument  
    "423", -- Shadowing a loop variable
    "431", -- Shadowing an upvalue
    "432", -- Shadowing an upvalue argument
    "433", -- Shadowing an upvalue loop variable
}

-- Exclude test files from some checks
files["tests/"] = {
    std = "+busted",
}