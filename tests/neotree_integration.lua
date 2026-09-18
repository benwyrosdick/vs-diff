-- Run with make test-neotree. Override VSDIFF_TEST_DEPS for non-lazy installations.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
local deps = vim.env.VSDIFF_TEST_DEPS or (vim.fn.stdpath("data") .. "/lazy")
for _, name in ipairs({ "neo-tree.nvim", "nui.nvim", "plenary.nvim" }) do
  vim.opt.rtp:append(deps .. "/" .. name)
end
require("neo-tree").setup({
  sources = { "filesystem", "vs_diff" },
  enable_git_status = false,
  enable_diagnostics = false,
})
local command = require("neo-tree.command")
local backend = require("vs-diff.neotree")
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local editor = vim.api.nvim_get_current_win()
command.execute({ source = "filesystem", action = "focus" })
vim.wait(300)
local sidebar = vim.api.nvim_get_current_win()
assert(sidebar ~= editor)
vim.api.nvim_set_current_win(editor)
backend.focus()
assert(vim.api.nvim_get_current_win() == sidebar, "focus must enter reused sidebar")
backend.toggle()
assert(not renderer.window_exists(manager.get_state("vs_diff")), "toggle must close")
command.execute({ source = "filesystem", action = "show" })
vim.wait(300)
vim.api.nvim_set_current_win(editor)
backend.toggle()
assert(vim.api.nvim_get_current_win() == manager.get_state("vs_diff").winid, "toggle must focus")
backend.close()
command.execute({ source = "filesystem", action = "show" })
vim.wait(300)
vim.api.nvim_set_current_win(editor)
backend.show()
vim.wait(300)
assert(vim.api.nvim_get_current_win() == editor, "show must preserve editor focus")
print("Neo-tree integration checks passed")
