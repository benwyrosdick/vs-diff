local tree = require("vs-diff.tree")
local git = require("vs-diff.git")
local render = require("vs-diff.render")
local A = vsdiff_assert

local records = git.parse_porcelain(table.concat({
  " M lua/vs-diff/init.lua",
  " M lua/vs-diff/git.lua",
  "M  README.md",
  "?? scratch.txt",
  "UU lua/conflict.lua",
}, "\0") .. "\0")

local entries = git.entries_from_records("/repo", records)
local nodes = tree.build(entries, "tree")

local lines, rows = render.lines(nodes, {})
A.is_true(#lines >= 5, "renders sections and files")
A.eq(rows[1].node.extra.section, "conflict")

local names = {}
for _, row in ipairs(rows) do
  names[#names + 1] = row.node.name
end
A.is_true(vim.tbl_contains(names, "Merge Changes (1)"))
A.is_true(vim.tbl_contains(names, "Staged Changes (1)"))
A.is_true(vim.tbl_contains(names, "Unstaged Changes (3)"))
A.is_true(vim.tbl_contains(names, "scratch.txt"))
A.is_true(vim.tbl_contains(names, "git.lua"))

local collapsed = { ["section:unstaged"] = true }
local collapsed_lines, collapsed_rows = render.lines(nodes, collapsed)
local collapsed_names = {}
for _, row in ipairs(collapsed_rows) do
  collapsed_names[#collapsed_names + 1] = row.node.name
end
A.is_true(vim.tbl_contains(collapsed_names, "Unstaged Changes (3)"))
A.is_true(not vim.tbl_contains(collapsed_names, "scratch.txt"))
A.is_true(#collapsed_rows < #rows, "collapsed section hides children")

local file_row
for _, row in ipairs(rows) do
  if row.node.name == "scratch.txt" then
    file_row = row
    break
  end
end
A.is_true(file_row ~= nil)
local line = render.format_row(file_row, {})
A.is_true(line:find("scratch.txt", 1, true) ~= nil)
A.is_true(line:find("│", 1, true) ~= nil)

return 8
