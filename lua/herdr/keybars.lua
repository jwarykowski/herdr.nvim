-- herdr.nvim's keybars Pro side, on with setup({ keybars = true }) or a table
-- of options: commands run through keybars-pro so the keyboard shows how they
-- went, errors held on a key while they last, and a statusline component for
-- the Focus timer and typing speed. Everything goes through the keybars-pro
-- command; nothing here talks to the keyboard itself.
local M = {}

local defaults = {
	cmd = "keybars-pro", -- the keybars-pro command
	run_name = "build", -- :KeybarsRun's events: build.running, build.passed, build.failed
	diagnostics = false, -- hold a key while any loaded buffer has errors
	diagnostics_key = "esc", -- keys as keybars-pro light names them
	diagnostics_colour = "red",
	statusline = { focus = true, typing = true },
}

local config = vim.tbl_deep_extend("force", {}, defaults)

-- command is the keybars-pro command in use.
function M.command()
	return config.cmd
end

-- run_args is the keybars-pro run command for a shell command.
local function run_args(cmd, name, shell_cmd)
	return { cmd, "run", "-q", "-name", name, "--", vim.o.shell, vim.o.shellcmdflag, shell_cmd }
end

-- status_text renders the latest focus and typing news: "🎯12m · 74 wpm".
local function status_text(state, opts)
	local parts = {}
	local f = state.focus
	if opts.focus and f and (f.phase == "work" or f.phase == "break") then
		local icon = f.phase == "work" and "🎯" or "☕"
		parts[#parts + 1] = ("%s%dm"):format(icon, math.ceil((f.remaining or 0) / 60))
	end
	local t = state.typing
	if opts.typing and t and (t.wpm or 0) > 0 then
		parts[#parts + 1] = ("%d wpm"):format(t.wpm)
	end
	return table.concat(parts, " · ")
end

-- errors counts error diagnostics across loaded buffers.
local function errors()
	return #vim.diagnostic.get(nil, { severity = vim.diagnostic.severity.ERROR })
end

-- run runs a shell command through keybars-pro run, so the keyboard shows it
-- running and then passed or failed, and puts its output in the quickfix list
-- when it fails.
function M.run(shell_cmd)
	if shell_cmd == "" then
		return vim.notify("keybars: :KeybarsRun needs a command, e.g. :KeybarsRun make test", vim.log.levels.WARN)
	end
	vim.notify("keybars: running " .. shell_cmd)
	vim.system(run_args(config.cmd, config.run_name, shell_cmd), { text = true }, function(r)
		vim.schedule(function()
			if r.code == 0 then
				vim.notify("keybars: " .. shell_cmd .. " passed")
				return
			end
			local out = vim.split((r.stdout or "") .. (r.stderr or ""), "\n", { trimempty = true })
			vim.fn.setqflist({}, " ", { title = shell_cmd, lines = out })
			vim.cmd("copen")
			vim.notify(("keybars: %s failed (%d)"):format(shell_cmd, r.code), vim.log.levels.WARN)
		end)
	end)
end

-- the diagnostics key: lit while any loaded buffer has errors, cleared when
-- none do; only changes reach keybars-pro
local lit = false

local function sync_diagnostics()
	local want = errors() > 0
	if want == lit then
		return
	end
	lit = want
	local args = want and { config.cmd, "light", config.diagnostics_key, config.diagnostics_colour, "-effect", "hold" }
		or { config.cmd, "clear", config.diagnostics_key }
	vim.system(args, { text = true })
end

-- the statusline's news, from one keybars-pro watch for the session
local state = {}
local job = nil
-- when the watch last started, so a closed app is retried every 30 seconds,
-- not on every redraw
local started = -math.huge

local function watch()
	local now = vim.uv.now()
	if job or now - started < 30000 then
		return
	end
	started = now
	local buf = ""
	job = vim.fn.jobstart({ config.cmd, "watch", "-only", "focus,typing" }, {
		stdout_buffered = false,
		on_stdout = function(_, data)
			-- data is chunks split on newlines; the last is a partial line
			data[1] = buf .. data[1]
			buf = data[#data]
			for i = 1, #data - 1 do
				local ok, ev = pcall(vim.json.decode, data[i])
				if ok and type(ev) == "table" and ev.event then
					state[ev.event] = ev.data
				end
			end
		end,
		on_exit = function()
			-- the app quit or isn't running: try again on a later redraw
			job = nil
			state = {}
		end,
	})
	if job <= 0 then
		job = nil
	end
end

-- status returns the Focus timer and typing speed for a statusline, or "".
-- The first call starts watching keybars Pro.
function M.status()
	watch()
	return status_text(state, config.statusline)
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", {}, defaults, type(opts) == "table" and opts or {})

	vim.api.nvim_create_user_command("KeybarsRun", function(a)
		M.run(a.args)
	end, { nargs = "+", complete = "shellcmd", desc = "run a command; the keyboard shows how it went" })

	vim.api.nvim_create_user_command("KeybarsFocus", function(a)
		local action = a.args ~= "" and a.args or "start"
		vim.system({ config.cmd, "focus", action }, { text = true }, function(r)
			vim.schedule(function()
				local msg = vim.trim((r.code == 0 and r.stdout or r.stderr) or "")
				vim.notify("keybars: focus " .. (msg ~= "" and msg or action))
			end)
		end)
	end, {
		nargs = "?",
		complete = function()
			return { "start", "stop", "status" }
		end,
		desc = "keybars Pro's Focus timer: start, stop or status",
	})

	if config.diagnostics then
		vim.api.nvim_create_autocmd("DiagnosticChanged", {
			group = vim.api.nvim_create_augroup("herdr_keybars", { clear = true }),
			callback = sync_diagnostics,
		})
	end
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("herdr_keybars_leave", { clear = true }),
		callback = function()
			if lit then
				vim.system({ config.cmd, "clear", config.diagnostics_key }):wait(1000)
			end
			if job then
				vim.fn.jobstop(job)
			end
		end,
	})
end

-- _internal exposes pure helpers for the test suite; not part of the public API.
M._internal = { run_args = run_args, status_text = status_text }

return M
