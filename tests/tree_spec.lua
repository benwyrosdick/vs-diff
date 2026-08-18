local tree = require("vs-diff.tree")
local git = require("vs-diff.git")
local A = vsdiff_assert

local records = git.parse_porcelain(table.concat({
  " M lua/vs-diff/init.lua",
  " M lua/vs-diff/git.lua",
  "M  README.md",
  "?? scratch.txt",
  "UU lua/conflict.lua",
}, "\0") .. "\0")

local entries = git.entries_from_records("/repo", records)
local nodes, expanded = tree.build(entries, "tree")

A.eq(#nodes, 3, "Merge, Staged, Unstaged sections")
A.eq(nodes[1].extra.section, "conflict")
A.eq(nodes[2].extra.section, "staged")
A.eq(nodes[3].extra.section, "unstaged")
A.eq(nodes[1].name, "Merge Changes (1)")
A.eq(nodes[2].name, "Staged Changes (1)")
A.eq(nodes[3].name, "Unstaged Changes (3)")

local changes = nodes[3]
local names = {}
for _, child in ipairs(changes.children) do
  names[#names + 1] = child.name .. ":" .. child.type
end
table.sort(names)
A.eq(names, { "lua:directory", "scratch.txt:file" })

local lua_dir
for _, child in ipairs(changes.children) do
  if child.name == "lua" then
    lua_dir = child
  end
end
A.is_true(lua_dir ~= nil)
A.eq(lua_dir.children[1].name, "vs-diff")
A.eq(#lua_dir.children[1].children, 2)
A.eq(#lua_dir.extra.entries, 2)

A.is_true(vim.tbl_contains(expanded, "section:unstaged"))
A.is_true(vim.tbl_contains(expanded, "dir:unstaged:lua/vs-diff"))

local list_nodes = tree.build(entries, "list")
local list_changes
for _, node in ipairs(list_nodes) do
  if node.extra.section == "unstaged" then
    list_changes = node
  end
end
A.eq(#list_changes.children, 3)
A.eq(list_changes.children[1].name, "git.lua")
A.eq(list_changes.children[1].extra.dirpath, "lua/vs-diff")
A.eq(list_changes.children[2].name, "init.lua")
A.eq(list_changes.children[3].name, "scratch.txt")
A.eq(list_changes.children[3].extra.dirpath, "")

local empty = tree.build({}, "tree")
A.eq(empty[1].type, "message")
A.eq(empty[1].name, "No changes")

local unstaged_only = {}
for _, e in ipairs(entries) do
  if e.section == "unstaged" then
    unstaged_only[#unstaged_only + 1] = e
  end
end
local dirty = tree.build(unstaged_only, "tree")
A.eq(#dirty, 2, "empty Staged section still shown")
A.eq(dirty[1].extra.section, "staged")
A.eq(dirty[1].name, "Staged Changes (0)")
A.eq(#dirty[1].children, 0)
A.eq(dirty[2].extra.section, "unstaged")
A.eq(dirty[2].name, "Unstaged Changes (3)")

return 9
