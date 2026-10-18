local M = {}

local defaults = {
	cmd = nil, -- herdr binary; nil = $HERDR_BIN_PATH, else "herdr"
	diagnostics = true, -- include diagnostics on the sent lines in the prompt
	scope = "workspace", -- "workspace": agents in this herdr workspace; "all": every agent
	keybars = false, -- true, or keybars options (lua/herdr/keybars.lua): keybars Pro commands and statusline
}

local config = vim.tbl_deep_extend("force", {}, defaults)

-- last is the pane id of the agent last sent to; :HerdrSend reuses it while it
-- is still running, and :HerdrSend! picks again.
local last = nil

-- binary returns the herdr command: config.cmd, else the binary herdr exports
-- into its panes, else herdr on $PATH.
function M.binary()
	return config.cmd or vim.env.HERDR_BIN_PATH or "herdr"
end

-- keybars_on reports whether setup turned on the keybars Pro side.
function M.keybars_on()
	return config.keybars and true or false
end

-- in_herdr reports whether nvim runs inside a herdr pane.
function M.in_herdr()
	return vim.env.HERDR_ENV == "1"
end

-- filter_agents keeps the agents a prompt may go to: never this pane, and only
-- this workspace unless scope is "all".
local function filter_agents(agents, scope, workspace, pane)
	local found = {}
	for _, a in ipairs(agents) do
		if a.pane_id ~= pane and (scope == "all" or a.workspace_id == workspace) then
			found[#found + 1] = a
		end
	end
	return found
end

-- agent_label renders an agent for the picker: kind, status, then its title.
local function agent_label(a)
	local s = a.agent
	if a.agent_status and a.agent_status ~= "" then
		s = s .. " [" .. a.agent_status .. "]"
	end
	return s .. "  " .. ((a.terminal_title_stripped ~= "" and a.terminal_title_stripped) or a.pane_id)
end

-- format_context renders where the code is: "file:line" for one line with no
-- selection, else "file:first-last" and the lines in a fenced block. diags are
-- { lnum (1-based), severity name, message } and follow as a list.
local function format_context(file, first, last_line, lines, ft, diags)
	local s
	if not lines then
		s = ("%s:%d"):format(file, first)
	else
		s = ("%s:%d-%d\n```%s\n%s\n```"):format(file, first, last_line, ft or "", table.concat(lines, "\n"))
	end
	if diags and #diags > 0 then
		local out = { "", "Diagnostics:" }
		for _, d in ipairs(diags) do
			out[#out + 1] = ("- %s:%d %s: %s"):format(file, d.lnum, d.severity:lower(), d.message)
		end
		s = s .. "\n" .. table.concat(out, "\n")
	end
	return s
end

-- build_prompt joins the instruction and the context.
local function build_prompt(instruction, ctx)
	return instruction .. "\n\n" .. ctx
end

-- context captures the current buffer's location: the cursor line, or the
-- given range { first, last } with its lines, plus diagnostics on those lines.
local function context(range)
	local file = vim.fn.expand("%:.")
	local first = range and range[1] or vim.fn.line(".")
	local last_line = range and range[2] or first
	local lines = range and vim.api.nvim_buf_get_lines(0, first - 1, last_line, false) or nil
	local diags = {}
	if config.diagnostics then
		for _, d in ipairs(vim.diagnostic.get(0)) do
			local lnum = d.lnum + 1
			if lnum >= first and lnum <= last_line then
				diags[#diags + 1] = {
					lnum = lnum,
					severity = vim.diagnostic.severity[d.severity] or "INFO",
					message = (d.message:gsub("%s+", " ")),
				}
			end
		end
	end
	return format_context(file, first, last_line, lines, vim.bo.filetype, diags)
end

-- agents asks herdr for the agents this session may prompt.
local function agents(cb)
	if not M.in_herdr() then
		return cb(nil, "not running inside herdr")
	end
	vim.system({ M.binary(), "agent", "list" }, { text = true }, function(r)
		vim.schedule(function()
			local ok, data = pcall(vim.json.decode, r.stdout or "")
			if r.code ~= 0 or not ok or type(data) ~= "table" or not data.result then
				return cb(nil, "herdr agent list failed")
			end
			cb(filter_agents(data.result.agents or {}, config.scope, vim.env.HERDR_WORKSPACE_ID, vim.env.HERDR_PANE_ID))
		end)
	end)
end

-- herdr runs a herdr subcommand async and reports failure.
local function herdr(args, ok_msg)
	local cmd = { M.binary() }
	vim.list_extend(cmd, args)
	vim.system(cmd, { text = true }, function(r)
		vim.schedule(function()
			if r.code == 0 then
				if ok_msg then
					vim.notify("herdr: " .. ok_msg)
				end
			else
				local msg = (r.stderr ~= "" and r.stderr) or r.stdout or ""
				vim.notify("herdr: " .. vim.trim(msg), vim.log.levels.ERROR)
			end
		end)
	end)
end

-- choose resolves the target agent: the last one while it is still around
-- (unless repick), the only one, or a picker. cb gets nil on cancel.
local function choose(list, repick, cb)
	if #list == 0 then
		vim.notify(
			"herdr: no other agent running" .. (config.scope == "all" and "" or " in this workspace"),
			vim.log.levels.WARN
		)
		return
	end
	if not repick and last then
		for _, a in ipairs(list) do
			if a.pane_id == last then
				return cb(a)
			end
		end
	end
	if #list == 1 then
		return cb(list[1])
	end
	vim.ui.select(list, { prompt = "agent", format_item = agent_label }, cb)
end

-- send asks for an instruction and sends it with the code under the cursor
-- (or range { first, last }) to an agent. repick ignores the remembered agent.
function M.send(range, repick)
	local ctx = context(range)
	agents(function(list, err)
		if not list then
			return vim.notify("herdr: " .. err, vim.log.levels.WARN)
		end
		choose(list, repick, function(a)
			if not a then
				return
			end
			last = a.pane_id
			vim.ui.input({ prompt = a.agent .. "> " }, function(text)
				if text and text ~= "" then
					herdr({ "agent", "prompt", a.pane_id, build_prompt(text, ctx) }, "sent to " .. a.agent)
				end
			end)
		end)
	end)
end

-- focus jumps to an agent's pane: the last one sent to, else pick.
function M.focus(repick)
	agents(function(list, err)
		if not list then
			return vim.notify("herdr: " .. err, vim.log.levels.WARN)
		end
		choose(list, repick, function(a)
			if a then
				last = a.pane_id
				herdr({ "agent", "focus", a.pane_id })
			end
		end)
	end)
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", {}, defaults, opts or {})

	vim.api.nvim_create_user_command("HerdrSend", function(a)
		M.send(a.range > 0 and { a.line1, a.line2 } or nil, a.bang)
	end, { range = true, bang = true, desc = "send the line / selection to a herdr agent (! = pick agent)" })

	vim.api.nvim_create_user_command("HerdrFocus", function(a)
		M.focus(a.bang)
	end, { bang = true, desc = "focus the herdr agent last sent to (! = pick agent)" })

	if config.keybars then
		require("herdr.keybars").setup(config.keybars)
	end
end

-- _internal exposes pure helpers for the test suite; not part of the public API.
M._internal = {
	filter_agents = filter_agents,
	agent_label = agent_label,
	format_context = format_context,
	build_prompt = build_prompt,
	set_config = function(c)
		last = nil
		config = vim.tbl_deep_extend("force", {}, defaults, c or {})
	end,
	set_last = function(p)
		last = p
	end,
	choose = choose,
}

return M
