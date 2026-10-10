local herdr = require("herdr")
local internal = herdr._internal

local agents = {
	{
		agent = "claude",
		agent_status = "idle",
		pane_id = "w1:p1",
		workspace_id = "w1",
		terminal_title_stripped = "fix",
	},
	{ agent = "codex", agent_status = "working", pane_id = "w1:p2", workspace_id = "w1", terminal_title_stripped = "" },
	{ agent = "claude", pane_id = "w2:p1", workspace_id = "w2", terminal_title_stripped = "other" },
}

describe("filter_agents", function()
	it("keeps this workspace's agents and never this pane", function()
		local got = internal.filter_agents(agents, "workspace", "w1", "w1:p2")
		assert.equals(1, #got)
		assert.equals("w1:p1", got[1].pane_id)
	end)

	it("spans every workspace with scope all", function()
		assert.equals(3, #internal.filter_agents(agents, "all", "w1", "w9:p9"))
	end)
end)

describe("agent_label", function()
	it("shows kind, status and title, falling back to the pane", function()
		assert.equals("claude [idle]  fix", internal.agent_label(agents[1]))
		assert.equals("codex [working]  w1:p2", internal.agent_label(agents[2]))
		assert.equals("claude  other", internal.agent_label(agents[3]))
	end)
end)

describe("format_context", function()
	it("is file:line for the cursor line", function()
		assert.equals("lua/a.lua:7", internal.format_context("lua/a.lua", 7, 7, nil, "lua", {}))
	end)

	it("fences a selection with its filetype", function()
		assert.equals(
			"a.go:3-4\n```go\nx := 1\ny := 2\n```",
			internal.format_context("a.go", 3, 4, { "x := 1", "y := 2" }, "go", {})
		)
	end)

	it("lists diagnostics after the code", function()
		local got = internal.format_context("a.go", 3, 3, nil, "go", {
			{ lnum = 3, severity = "ERROR", message = "undefined: y" },
		})
		assert.equals("a.go:3\n\nDiagnostics:\n- a.go:3 error: undefined: y", got)
	end)
end)

describe("build_prompt", function()
	it("puts the instruction before the context", function()
		assert.equals("why?\n\na.go:3", internal.build_prompt("why?", "a.go:3"))
	end)
end)

describe("choose", function()
	local select
	before_each(function()
		internal.set_config({})
		select = vim.ui.select
	end)
	after_each(function()
		vim.ui.select = select
	end)

	local function pick(list, repick)
		local got
		internal.choose(list, repick, function(a)
			got = a
		end)
		return got
	end

	it("takes the only agent without asking", function()
		vim.ui.select = function()
			error("should not ask")
		end
		assert.equals("w1:p1", pick({ agents[1] }).pane_id)
	end)

	it("reuses the last agent while it is still running", function()
		internal.set_last("w1:p2")
		vim.ui.select = function()
			error("should not ask")
		end
		assert.equals("w1:p2", pick({ agents[1], agents[2] }).pane_id)
	end)

	it("asks again when repicking or the last agent is gone", function()
		local asked = 0
		vim.ui.select = function(list, _, cb)
			asked = asked + 1
			cb(list[1])
		end
		internal.set_last("w1:p2")
		assert.equals("w1:p1", pick({ agents[1], agents[2] }, true).pane_id)
		internal.set_last("gone")
		assert.equals("w1:p1", pick({ agents[1], agents[2] }).pane_id)
		assert.equals(2, asked)
	end)
end)
