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

---Unified patch for one SCM entry. git-diff exits 1 when the files differ.
function M.unified_diff(root, entry)
  if not entry then
    return nil, "No file"
  end
  local args = { "diff", "--no-color", "--no-ext-diff" }
  if entry.section == "conflict" then
    args[#args + 1] = "--cc"
  elseif entry.section == "staged" then
    args[#args + 1] = "--cached"
  end
  if entry.kind == "untracked" then
    local null = vim.fn.has("win32") == 1 and "NUL" or "/dev/null"
    args = { "diff", "--no-color", "--no-ext-diff", "--no-index", "--", null, entry.relpath }
  else
    args[#args + 1] = "--"
    args[#args + 1] = entry.relpath
  end
  local stdout, stderr, code = run(root, args)
  if code > 1 then
    return nil, (stderr ~= "" and stderr or stdout)
  end
  return stdout or ""
end

function M.staged_diff(root)
  local stdout, stderr, code = run(root, { "diff", "--cached", "--no-color" })
  if code ~= 0 then
    return nil, stderr ~= "" and stderr or stdout
  end
  return stdout
end

function M.commit(root, message)
  if not message or vim.trim(message) == "" then
    return false, "Commit message is empty"
  end
  local tmp = vim.fn.tempname()
  vim.fn.writefile(util.split_lines(message), tmp)
  local _, stderr, code = run(root, { "commit", "-F", tmp })
  pcall(vim.fn.delete, tmp)
  if code ~= 0 then
    return false, stderr
  end
  return true
end

---Parse `git rev-list --left-right --count A...B` (`ahead<TAB>behind`).
function M.parse_ahead_behind(output)
  output = vim.trim(output or "")
  local ahead, behind = output:match("^(%d+)%s+(%d+)$")
  return tonumber(ahead) or 0, tonumber(behind) or 0
end

---Parse the first line of `git status -sb`.
---@param line string
---@return { branch: string|nil, upstream: string|nil, ahead: integer, behind: integer, gone: boolean }
function M.parse_short_branch(line)
  line = vim.trim(line or "")
  line = line:gsub("^##%s+", "")

  local empty = { branch = nil, upstream = nil, ahead = 0, behind = 0, gone = false }
  if line == "" then
    return empty
  end

  if line:find("^HEAD %(no branch%)") then
    return { branch = "HEAD", upstream = nil, ahead = 0, behind = 0, gone = false }
  end

  local rest = line:match("^No commits yet on (.+)$") or line
  local branch, upstream, tracking = rest:match("^(.-)%.%.%.(%S+)(.*)$")
  if not branch then
    branch = rest:match("^(%S+)")
    return { branch = branch, upstream = nil, ahead = 0, behind = 0, gone = false }
  end

  local gone = tracking:find("[gone]", 1, true) ~= nil
  local ahead = tonumber(tracking:match("ahead (%d+)")) or 0
  local behind = tonumber(tracking:match("behind (%d+)")) or 0
  return {
    branch = branch,
    upstream = (not gone) and upstream or nil,
    ahead = ahead,
    behind = behind,
    gone = gone,
  }
end

function M.default_remote(root)
  local stdout, _, code = run(root, { "remote" })
  if code ~= 0 then
    return nil
  end
  return vim.trim(stdout):match("([^\n]+)")
end

---Upstream ahead/behind plus default remote (for Publish).
function M.branch_status(root)
  local stdout, stderr, code = run(root, { "status", "-sb", "--untracked-files=no" })
  if code ~= 0 then
    return nil, (stderr ~= "" and stderr or stdout)
  end
  local first = stdout:match("([^\n]*)") or ""
  local info = M.parse_short_branch(first)
  if not info.upstream then
    info.remote = M.default_remote(root)
  end
  return info
end

local function run_ok(root, args)
  local stdout, stderr, code = run(root, args)
  if code ~= 0 then
    local err = vim.trim((stderr ~= "" and stderr or stdout) or "")
    return false, err ~= "" and err or ("git " .. args[1] .. " failed")
  end
  return true, stdout
end

function M.push(root)
  return run_ok(root, { "push" })
end

function M.pull(root)
  -- --no-edit: a merge pull must not open COMMIT_EDITMSG in the editor
  return run_ok(root, { "pull", "--no-edit" })
end

function M.publish(root, remote)
  remote = remote or M.default_remote(root)
  if not remote or remote == "" then
    return false, "No remote configured"
  end
  return run_ok(root, { "push", "-u", remote, "HEAD" })
end

function M.sync(root)
  local ok, err = M.pull(root)
  if not ok then
    return false, err
  end
  return M.push(root)
end

---Run a git argv list asynchronously. `on_done(ok, err_or_stdout, stdout)`.
function M.run_async(root, args, on_done)
  local cmd = { "git" }
  if root and root ~= "" then
    cmd[#cmd + 1] = "-C"
    cmd[#cmd + 1] = root
  end
  vim.list_extend(cmd, args)

  local function finish(stdout, stderr, code)
    local ok = (code or 1) == 0
    local err = vim.trim((stderr or "") .. ((not ok and stdout and stdout ~= "") and ("\n" .. stdout) or ""))
    if not ok and err == "" then
      err = "git " .. (args[1] or "command") .. " failed"
    end
    on_done(ok, ok and (stdout or "") or err, stdout or "")
  end

  if not vim.system then
    local stdout, stderr, code = run(root, args)
    finish(stdout, stderr, code)
    return
  end

  vim.system(cmd, { text = true }, function(result)
    vim.schedule(function()
      finish(result.stdout, result.stderr, result.code)
    end)
  end)
end

function M.fire_git_event()
  local ok, events = pcall(require, "neo-tree.events")
  if ok then
    events.fire_event(events.GIT_EVENT)
  end
  pcall(vim.api.nvim_exec_autocmds, "User", { pattern = "FugitiveChanged", modeline = false })
end

return M
