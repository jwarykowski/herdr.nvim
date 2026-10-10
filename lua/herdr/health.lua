local M = {}

function M.check()
	local health = vim.health
	health.start("herdr")

	local herdr = require("herdr")
	local cmd = herdr.binary()
	if vim.fn.executable(cmd) == 0 then
		health.error("`" .. cmd .. "` not found", {
			"install herdr: https://herdr.dev",
			"or set `cmd` in setup() to the binary path",
		})
		return
	end
	health.ok("`" .. cmd .. "` found: " .. vim.fn.exepath(cmd))

	if not herdr.in_herdr() then
		health.warn("nvim is not running inside a herdr pane", {
			"start nvim from a herdr pane; :HerdrSend talks to agents in its workspace",
		})
		return
	end
	health.ok(
		"inside herdr: workspace " .. (vim.env.HERDR_WORKSPACE_ID or "?") .. ", pane " .. (vim.env.HERDR_PANE_ID or "?")
	)

	local r = vim.system({ cmd, "agent", "list" }, { text = true }):wait()
	if r.code == 0 then
		health.ok("`herdr agent list` works")
	else
		health.error("`herdr agent list` exited " .. r.code .. ": " .. vim.trim(r.stderr or ""))
	end
end

return M
