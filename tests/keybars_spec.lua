local keybars = require("herdr.keybars")
local internal = keybars._internal

describe("run_args", function()
	it("runs the command through keybars-pro run, in the shell", function()
		local args = internal.run_args("keybars-pro", "build", "make test")
		assert.same({ "keybars-pro", "run", "-q", "-name", "build", "--" }, vim.list_slice(args, 1, 6))
		assert.equals("make test", args[#args])
	end)
end)

describe("status_text", function()
	local all = { focus = true, typing = true }

	it("shows the Focus timer in minutes and the typing speed", function()
		local s = { focus = { phase = "work", remaining = 700 }, typing = { wpm = 74 } }
		assert.equals("🎯12m · 74 wpm", internal.status_text(s, all))
		assert.equals("☕1m", internal.status_text({ focus = { phase = "break", remaining = 30 } }, all))
	end)

	it("leaves out what's idle or turned off", function()
		assert.equals("", internal.status_text({ focus = { phase = "" }, typing = { wpm = 0 } }, all))
		assert.equals("", internal.status_text({}, all))
		local s = { focus = { phase = "work", remaining = 60 }, typing = { wpm = 50 } }
		assert.equals("50 wpm", internal.status_text(s, { focus = false, typing = true }))
	end)
end)

describe("commands", function()
	local dir, log

	-- a fake keybars-pro: records its arguments; run exits with $FAKE_RUN_CODE
	before_each(function()
		dir = vim.fn.tempname()
		vim.fn.mkdir(dir, "p")
		log = dir .. "/log"
		local fake = dir .. "/keybars-pro"
		vim.fn.writefile({
			"#!/bin/sh",
			'echo "$*" >>' .. vim.fn.shellescape(log),
			'[ "$1" = run ] && { echo "main.go:3:1: boom"; exit 2; }',
			"exit 0",
		}, fake)
		vim.fn.setfperm(fake, "rwxr-xr-x")
		keybars.setup({ cmd = fake, diagnostics = true })
	end)

	after_each(function()
		vim.fn.delete(dir, "rf")
	end)

	local function logged()
		return vim.fn.filereadable(log) == 1 and vim.fn.readfile(log) or {}
	end

	it("puts a failed run's output in the quickfix list", function()
		vim.fn.setqflist({}, "f")
		vim.cmd("KeybarsRun go test ./...")
		assert.is_true(vim.wait(3000, function()
			return #vim.fn.getqflist() > 0
		end))
		assert.matches("^run %-q %-name build %-%- ", logged()[1])
		assert.equals("go test ./...", vim.fn.getqflist({ title = 1 }).title)
		vim.cmd("cclose")
	end)

	it("holds the diagnostics key while there are errors, and clears it after", function()
		local buf = vim.api.nvim_create_buf(false, true)
		local ns = vim.api.nvim_create_namespace("keybars_spec")
		vim.diagnostic.set(
			ns,
			buf,
			{ { lnum = 0, col = 0, message = "bad", severity = vim.diagnostic.severity.ERROR } }
		)
		assert.is_true(vim.wait(3000, function()
			return vim.tbl_contains(logged(), "light esc red -effect hold")
		end))
		vim.diagnostic.reset(ns, buf)
		assert.is_true(vim.wait(3000, function()
			return vim.tbl_contains(logged(), "clear esc")
		end))
	end)
end)
