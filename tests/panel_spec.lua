local vs = require("vs-diff")
local panel = require("vs-diff.panel")
local A = vsdiff_assert

vs.setup({})
panel.focus()
A.is_true(panel.is_open(), "panel opens")
local win = panel.win()
A.is_true(type(win) == "number")
local buf = vim.api.nvim_win_get_buf(win)
A.eq(vim.bo[buf].filetype, "vs-diff")
A.is_true(panel.current_node() ~= nil, "cursor sits on a node")

panel.close()
A.is_true(not panel.is_open(), "panel closes")

panel.toggle()
A.is_true(panel.is_open(), "toggle opens")
panel.toggle()
A.is_true(not panel.is_open(), "toggle closes")

return 6
