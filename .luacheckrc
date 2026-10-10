std = "luajit"
read_globals = { "vim" }
exclude_files = { ".luarocks" }

files["tests/"] = {
	std = "+busted",
	globals = { "vim" }, -- specs stub vim.ui.select
}
