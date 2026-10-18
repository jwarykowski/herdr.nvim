<p align="center"><img src="assets/herdr.nvim.svg" alt="herdr.nvim" width="120"></p>

# herdr.nvim

Send code from Neovim to a coding agent running in [herdr](https://herdr.dev),
without leaving the editor.

Select some lines, run `:HerdrSend`, type what you want ("why does this panic?",
"add a test for this"), and the agent in the next pane gets your instruction
plus `file:line` and the code in a fenced block, along with any diagnostics on
those lines. Works with any agent herdr runs: Claude Code, Codex, OpenCode, and
others.

- [requirements](#requirements)
- [install](#install)
- [usage](#usage)
- [configuration](#configuration)
- [keybars Pro](#keybars-pro)
- [development](#development)
- [support](#support)

## requirements

- Neovim ≥ 0.11 (`vim.system`, `vim.ui`).
- [herdr](https://herdr.dev), with nvim running inside a herdr pane and an
  agent in another pane of the same workspace.

## install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
return {
	"jwarykowski/herdr.nvim",
	cmd = { "HerdrSend", "HerdrFocus" },
	keys = {
		{ "<leader>ai", "<cmd>HerdrSend<cr>", desc = "agent: ask about this line" },
		{ "<leader>ai", ":HerdrSend<cr>", mode = "x", desc = "agent: ask about selection" },
		{ "<leader>aI", "<cmd>HerdrSend!<cr>", desc = "agent: ask, picking the agent" },
		{ "<leader>af", "<cmd>HerdrFocus<cr>", desc = "agent: focus its pane" },
	},
	opts = {},
}
```

Other plugin managers: add the repo and call `require("herdr").setup()`.

## usage

- `:HerdrSend` — prompt for an instruction and send it with the cursor's
  `file:line` to an agent. With a range (`:'<,'>HerdrSend`, or from visual
  mode) it sends `file:first-last` and the lines in a fenced block.
- Agent choice: with one agent in the workspace it goes straight there; with
  several you pick, and later sends reuse that agent while it is still running.
  `:HerdrSend!` picks again.
- Diagnostics (errors, warnings) on the sent lines are appended, so "fix this"
  needs no copy-pasting.
- `:HerdrFocus` — jump to the agent's pane (the last one sent to, else pick);
  `:HerdrFocus!` picks.

The pane nvim runs in is never offered, so an agent running nvim can't prompt
itself.

Run `:checkhealth herdr` to check the binary, the pane, and `herdr agent list`.

## configuration

```lua
require("herdr").setup({
	cmd = nil, -- herdr binary; default $HERDR_BIN_PATH, else herdr on $PATH
	diagnostics = true, -- append diagnostics on the sent lines
	scope = "workspace", -- or "all": offer agents from every herdr workspace
	keybars = false, -- true, or a table of the options below
})
```

## keybars Pro

With [keybars Pro](https://keybars.app/pro/) and its `keybars-pro` command,
`keybars = true` adds the keyboard's side of the editor. Everything goes
through [`keybars-pro`](https://keybars.app/pro/cli/), so it works on any
keyboard keybars Pro drives.

- `:KeybarsRun make test` runs a command through `keybars-pro run`, so the
  keyboard shows `build.running`, then `build.passed` or `build.failed` (the
  marketplace's CI pack plays them), and a failure's output opens in the
  quickfix list.
- `:KeybarsFocus [start|stop|status]` drives keybars Pro's Focus timer.
- `require("herdr.keybars").status()` is a statusline component: `🎯12m · 74
  wpm` while Focus or Typing runs, else `""`. It follows one `keybars-pro
  watch` for the session, so it's cheap on every redraw.
- With `diagnostics = true`, a key holds red while any loaded buffer has
  errors, and clears when they're fixed.

[herdr-keybars](https://code.warykowski.io/jwarykowski/herdr-keybars) lights
your agents' workspaces; this is the editor's half.

```lua
opts = {
	keybars = {
		cmd = "keybars-pro", -- the command, if it isn't on $PATH
		run_name = "build", -- :KeybarsRun's events: <name>.running, .passed, .failed
		diagnostics = false, -- hold a key while there are errors
		diagnostics_key = "esc", -- as keybars-pro light names keys: esc, top-right, r2c1...
		diagnostics_colour = "red",
		statusline = { focus = true, typing = true },
	},
},
```

With lualine:

```lua
sections = {
	lualine_x = { function() return require("herdr.keybars").status() end, "filetype" },
},
```

`:checkhealth herdr` also checks `keybars-pro` answers when this is on.

## development

```sh
make fmt     # stylua
make lint    # stylua --check + luacheck
make test    # busted (specs run under Neovim via nlua)
make check   # lint + test
```

Test deps: `luarocks install busted nlua`. The specs cover the pure helpers
(agent filtering, labels, the prompt and context format, agent choice) exposed
on `require("herdr")._internal`; CI runs them on Neovim stable and nightly.

## support

herdr.nvim is free and MIT licensed. If it saves you some copy and paste, you
can [sponsor its development](https://github.com/sponsors/jwarykowski).

## license

[MIT](LICENSE)
