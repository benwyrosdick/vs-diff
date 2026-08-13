local git = require("vs-diff.git")
local A = vsdiff_assert

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

local function git_cmd(args)
  local stdout, stderr, code = git.run(tmp, args)
  if code ~= 0 then
    error(string.format("git %s failed: %s%s", table.concat(args, " "), stdout, stderr))
  end
  return stdout
end

local function write_file(rel, contents)
  local path = tmp .. "/" .. rel
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  vim.fn.writefile(vim.split(contents, "\n", { plain = true }), path)
end

local ok, err = pcall(function()
  git_cmd({ "init" })
  git_cmd({ "config", "user.email", "vs-diff@test.local" })
  git_cmd({ "config", "user.name", "vs-diff" })
  write_file("tracked.lua", "one\n")
  write_file("keep.lua", "keep\n")
  git_cmd({ "add", "." })
  git_cmd({ "commit", "-m", "init" })

  write_file("tracked.lua", "one\ntwo\n")
  write_file("lua/new.lua", "new\n")
  write_file("keep.lua", "changed\n")

  local entries = assert(git.status(tmp))
  local by = {}
  for _, e in ipairs(entries) do
    by[e.section .. ":" .. e.relpath] = e
  end
  A.is_true(by["unstaged:tracked.lua"] ~= nil, "modified file is unstaged")
  A.eq(by["unstaged:tracked.lua"].kind, "modified")
  A.eq(by["unstaged:lua/new.lua"].kind, "untracked")
  A.eq(by["unstaged:keep.lua"].kind, "modified")

  A.is_true(select(1, git.stage(tmp, { by["unstaged:tracked.lua"].path })))
  entries = assert(git.status(tmp))
  by = {}
  for _, e in ipairs(entries) do
    by[e.section .. ":" .. e.relpath] = e
  end
  A.is_true(by["staged:tracked.lua"] ~= nil, "file moved to staged")
  A.is_true(by["unstaged:tracked.lua"] == nil, "file left Changes")

  A.is_true(select(1, git.unstage(tmp, { by["staged:tracked.lua"].path })))
  entries = assert(git.status(tmp))
  by = {}
  for _, e in ipairs(entries) do
    by[e.section .. ":" .. e.relpath] = e
  end
  A.is_true(by["unstaged:tracked.lua"] ~= nil, "file returned to Changes")

  A.is_true(select(1, git.discard(tmp, { by["unstaged:keep.lua"] })))
  local keep = table.concat(vim.fn.readfile(tmp .. "/keep.lua"), "\n")
  A.is_true(keep:find("keep", 1, true) ~= nil, "discard restored keep.lua")
  A.is_true(keep:find("changed", 1, true) == nil)

  A.is_true(select(1, git.discard(tmp, { by["unstaged:lua/new.lua"] })))
  A.eq(vim.fn.filereadable(tmp .. "/lua/new.lua"), 0, "untracked file deleted")

  write_file("tracked.lua", "one\npatched\n")
  entries = assert(git.status(tmp))
  local tracked
  for _, e in ipairs(entries) do
    if e.relpath == "tracked.lua" and e.section == "unstaged" then
      tracked = e
    end
  end
  A.is_true(tracked ~= nil)
  local patch = assert(git.unified_diff(tmp, tracked))
  A.is_true(patch:find("%+patched", 1) ~= nil or patch:find("+patched", 1, true) ~= nil)
end)
vim.fn.delete(tmp, "rf")
if not ok then
  error(err)
end
return 7
