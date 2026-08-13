local util = require("vs-diff.util")

local M = {}

---@class vsdiff.Entry
---@field path string
---@field relpath string
---@field orig_path string|nil
---@field orig_relpath string|nil
---@field section "unstaged"|"staged"|"conflict"
---@field kind "modified"|"added"|"deleted"|"untracked"|"renamed"|"conflict"
---@field letter string
---@field xy string

local function run(root, args)
  local cmd = { "git" }
  if root and root ~= "" then
    cmd[#cmd + 1] = "-C"
    cmd[#cmd + 1] = root
  end
  vim.list_extend(cmd, args)
  if vim.system then
    local result = vim.system(cmd, { text = true }):wait()
    return result.stdout or "", result.stderr or "", result.code or 1
  end
  local stdout = vim.fn.system(cmd)
  return stdout, "", vim.v.shell_error
end

function M.run(root, args)
  return run(root, args)
end

function M.root(path)
  path = path or vim.fn.getcwd()
  local stdout, _, code = run(path, { "rev-parse", "--show-toplevel" })
  if code ~= 0 then
    return nil
  end
  local root = vim.trim(stdout)
  if root == "" then
    return nil
  end
  return util.normalize(root)
end

function M.has_head(root)
  local _, _, code = run(root, { "rev-parse", "--verify", "HEAD" })
  return code == 0
end

---Parse `git status --porcelain=v1 -z` output into raw records.
---@param output string
---@return { x: string, y: string, path: string, orig_path: string|nil }[]
function M.parse_porcelain(output)
  local records = {}
  if not output or output == "" then
    return records
  end

  local parts = {}
  for part in output:gmatch("([^%z]+)") do
    parts[#parts + 1] = part
  end

  -- Fall back to newline-delimited porcelain if the output is not NUL-separated.
  if #parts == 1 and output:find("\n") and not output:find("\0", 1, true) then
    parts = {}
    for line in output:gmatch("([^\n]+)") do
      parts[#parts + 1] = line
    end
    local i = 1
    while i <= #parts do
      local line = parts[i]
      local x, y, rest = line:match("^(.)(.) (.*)$")
      if x then
        local path, orig
        if (x == "R" or x == "C") and rest:find(" -> ", 1, true) then
          orig, path = rest:match("^(.*) %-> (.*)$")
        else
          path = rest
        end
        records[#records + 1] = { x = x, y = y, path = path, orig_path = orig }
      end
      i = i + 1
    end
    return records
  end

  local i = 1
  while i <= #parts do
    local rec = parts[i]
    local x, y, path = rec:match("^(.)(.) (.*)$")
    if x and path then
      local orig
      if x == "R" or x == "C" then
        i = i + 1
        orig = parts[i]
      end
      records[#records + 1] = { x = x, y = y, path = path, orig_path = orig }
    end
    i = i + 1
  end
  return records
end

local function letter_for(kind)
  local map = {
    modified = "M",
    added = "A",
    deleted = "D",
    untracked = "U",
    renamed = "R",
    conflict = "C",
  }
  return map[kind] or "M"
end

local function kind_from_code(code, untracked)
  if untracked then
    return "untracked"
  end
  if code == "A" then
    return "added"
  end
  if code == "D" then
    return "deleted"
  end
  if code == "R" or code == "C" then
    return "renamed"
  end
  return "modified"
end

local function is_conflict(x, y)
  return x == "U" or y == "U" or (x == "A" and y == "A") or (x == "D" and y == "D")
end

---Turn porcelain records into VS Code-style section entries.
---@param root string
---@param records table
---@return vsdiff.Entry[]
function M.entries_from_records(root, records)
  local entries = {}

  local function add(section, relpath, orig_relpath, kind, xy)
    local path = util.join(root, relpath)
    local orig_path = orig_relpath and util.join(root, orig_relpath) or nil
    entries[#entries + 1] = {
      path = util.normalize(path),
      relpath = relpath:gsub("\\", "/"),
      orig_path = orig_path and util.normalize(orig_path) or nil,
      orig_relpath = orig_relpath,
      section = section,
      kind = kind,
      letter = letter_for(kind),
      xy = xy,
    }
  end

  for _, rec in ipairs(records) do
    local x, y = rec.x, rec.y
    local xy = x .. y
    if x ~= "!" then
      if is_conflict(x, y) then
        add("conflict", rec.path, rec.orig_path, "conflict", xy)
      else
        if x == "?" and y == "?" then
          add("unstaged", rec.path, rec.orig_path, "untracked", xy)
        else
          if x ~= " " and x ~= "?" then
            add("staged", rec.path, rec.orig_path, kind_from_code(x, false), xy)
          end
          if y ~= " " and y ~= "?" then
            add("unstaged", rec.path, rec.orig_path, kind_from_code(y, false), xy)
          end
        end
      end
    end
  end

  table.sort(entries, function(a, b)
    if a.section ~= b.section then
      return a.section < b.section
    end
    return a.relpath < b.relpath
  end)

  return entries
end

function M.status(root)
  root = root or M.root()
  if not root then
    return nil, "Not a git repository"
  end
  local stdout, stderr, code = run(root, {
    "status",
    "--porcelain=v1",
    "-z",
    "--untracked-files=all",
  })
  if code ~= 0 then
    return nil, (stderr ~= "" and stderr or stdout)
  end
  return M.entries_from_records(root, M.parse_porcelain(stdout)), nil, root
end

function M.show(root, spec)
  local stdout, stderr, code = run(root, { "show", spec })
  if code ~= 0 then
    return nil, stderr ~= "" and stderr or stdout
  end
  return stdout
end

function M.stage(root, paths)
  if not paths or #paths == 0 then
    return true
  end
  local args = { "add", "--" }
  vim.list_extend(args, paths)
  local _, stderr, code = run(root, args)
  if code ~= 0 then
    return false, stderr
  end
  return true
end

function M.unstage(root, paths)
  if not paths or #paths == 0 then
    return true
  end
  local args
  if M.has_head(root) then
    args = { "restore", "--staged", "--" }
  else
    args = { "rm", "--cached", "-f", "--" }
  end
  vim.list_extend(args, paths)
  local _, stderr, code = run(root, args)
  if code ~= 0 then
    return false, stderr
  end
  return true
end

---Discard unstaged worktree changes. Untracked files are deleted.
function M.discard(root, entries)
  local restore = {}
  local untracked = {}
  for _, entry in ipairs(entries) do
    if entry.section == "conflict" then
      return false, "Cannot discard a conflicted file from vs-diff"
    end
    if entry.kind == "untracked" then
      untracked[#untracked + 1] = entry.path
    else
      restore[#restore + 1] = entry.path
    end
  end

  if #restore > 0 then
    local args = { "restore", "--worktree", "--" }
    vim.list_extend(args, restore)
    local _, stderr, code = run(root, args)
    if code ~= 0 then
      return false, stderr
    end
  end

  for _, path in ipairs(untracked) do
    local stat = (vim.uv or vim.loop).fs_stat(path)
    if stat and stat.type == "directory" then
      vim.fn.delete(path, "rf")
    else
      vim.fn.delete(path)
    end
  end

  return true
end

function M.commit(root, message)
  if not message or vim.trim(message) == "" then
    return false, "Commit message is empty"
  end
  local _, stderr, code = run(root, { "commit", "-m", message })
  if code ~= 0 then
    return false, stderr
  end
  return true
end

function M.fire_git_event()
  local ok, events = pcall(require, "neo-tree.events")
  if ok then
    events.fire_event(events.GIT_EVENT)
  end
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "FugitiveChanged", modeline = false })
end

return M
