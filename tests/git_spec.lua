local git = require("vs-diff.git")
local A = vsdiff_assert

local function count(entries, section, kind)
  local n = 0
  for _, e in ipairs(entries) do
    if e.section == section and (not kind or e.kind == kind) then
      n = n + 1
    end
  end
  return n
end

-- NUL-separated porcelain
local z = table.concat({
  " M lua/foo.lua",
  "M  lua/bar.lua",
  "MM lua/both.lua",
  "?? new.txt",
  "D  gone.lua",
  "R  lua/renamed.lua",
  "lua/old.lua",
  "UU lua/conflict.lua",
}, "\0") .. "\0"

local records = git.parse_porcelain(z)
A.eq(#records, 7, "parsed 7 porcelain records")
A.eq(records[1].x, " ")
A.eq(records[1].y, "M")
A.eq(records[1].path, "lua/foo.lua")
A.eq(records[6].x, "R")
A.eq(records[6].path, "lua/renamed.lua")
A.eq(records[6].orig_path, "lua/old.lua")
A.eq(records[7].x, "U")
A.eq(records[7].y, "U")

-- newline fallback, including rename arrow form
local nl = table.concat({
  " M lua/foo.lua",
  "R  lua/old.lua -> lua/renamed.lua",
  "?? new.txt",
}, "\n") .. "\n"
local nl_records = git.parse_porcelain(nl)
A.eq(#nl_records, 3, "newline porcelain")
A.eq(nl_records[2].path, "lua/renamed.lua")
A.eq(nl_records[2].orig_path, "lua/old.lua")

local entries = git.entries_from_records("/repo", records)
A.eq(count(entries, "unstaged", "modified"), 2, "unstaged modified: foo + both")
A.eq(count(entries, "staged", "modified"), 2, "staged modified: bar + both")
A.eq(count(entries, "unstaged", "untracked"), 1)
A.eq(count(entries, "staged", "deleted"), 1)
A.eq(count(entries, "staged", "renamed"), 1)
A.eq(count(entries, "conflict"), 1)
A.is_true(count(entries, "unstaged") + count(entries, "staged") + count(entries, "conflict") == #entries)

local both
for _, e in ipairs(entries) do
  if e.relpath == "lua/both.lua" and e.section == "unstaged" then
    both = e
  end
end
A.is_true(both ~= nil, "MM file appears in Changes")
A.eq(both.letter, "M")

local renamed
for _, e in ipairs(entries) do
  if e.kind == "renamed" then
    renamed = e
  end
end
A.eq(renamed.orig_relpath, "lua/old.lua")
A.eq(renamed.letter, "R")

-- ignored records are dropped
local ignored = git.entries_from_records("/repo", git.parse_porcelain("!! skip.me\0"))
A.eq(#ignored, 0)

A.eq({ git.parse_ahead_behind("2\t1\n") }, { 2, 1 })
A.eq({ git.parse_ahead_behind("0 4") }, { 0, 4 })
A.eq({ git.parse_ahead_behind("") }, { 0, 0 })

local sb = git.parse_short_branch("## main...origin/main [ahead 2, behind 1]")
A.eq(sb.branch, "main")
A.eq(sb.upstream, "origin/main")
A.eq(sb.ahead, 2)
A.eq(sb.behind, 1)

local ahead_only = git.parse_short_branch("## feat/foo...origin/feat/foo [ahead 3]")
A.eq(ahead_only.branch, "feat/foo")
A.eq(ahead_only.ahead, 3)
A.eq(ahead_only.behind, 0)

local behind_only = git.parse_short_branch("## main...origin/main [behind 4]")
A.eq(behind_only.behind, 4)
A.eq(behind_only.ahead, 0)

local local_only = git.parse_short_branch("## main")
A.eq(local_only.branch, "main")
A.eq(local_only.upstream, nil)

local gone = git.parse_short_branch("## main...origin/main [gone]")
A.eq(gone.upstream, nil)
A.eq(gone.gone, true)

local detached = git.parse_short_branch("## HEAD (no branch)")
A.eq(detached.branch, "HEAD")

local fresh = git.parse_short_branch("## No commits yet on main")
A.eq(fresh.branch, "main")

return 18
