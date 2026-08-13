local git = require("vs-diff.git")
local tree = require("vs-diff.tree")
local util = require("vs-diff.util")
local config = require("vs-diff.config")

local M = {}

local function paths(entries)
  local list = {}
  local seen = {}
  for _, entry in ipairs(entries) do
    if entry.path and not seen[entry.path] then
      seen[entry.path] = true
      list[#list + 1] = entry.path
    end
  end
  return list
end

local function filter(entries, section)
  if not section then
    return entries
  end
  local out = {}
  for _, entry in ipairs(entries) do
    if entry.section == section then
      out[#out + 1] = entry
    end
  end
  return out
end

local function after(ok, err, success_msg)
  if not ok then
    util.notify(err or "git command failed", vim.log.levels.ERROR)
    return
  end
  if success_msg then
    util.notify(success_msg)
  end
  git.fire_git_event()
end

function M.entries_from_node(node)
  return tree.collect_entries(node)
end

function M.entries_from_nodes(nodes)
  local list = {}
  local seen = {}
  for _, node in ipairs(nodes or {}) do
    for _, entry in ipairs(tree.collect_entries(node)) do
      local key = entry.section .. ":" .. entry.path
      if not seen[key] then
        seen[key] = true
        list[#list + 1] = entry
      end
    end
  end
  return list
end

function M.stage(root, entries)
  entries = filter(entries, "unstaged")
  if #entries == 0 then
    util.notify("Nothing to stage")
    return
  end
  local ok, err = git.stage(root, paths(entries))
  after(ok, err, string.format("Staged %d file(s)", #entries))
end

function M.unstage(root, entries)
  entries = filter(entries, "staged")
  if #entries == 0 then
    util.notify("Nothing to unstage")
    return
  end
  local ok, err = git.unstage(root, paths(entries))
  after(ok, err, string.format("Unstaged %d file(s)", #entries))
end

function M.discard(root, entries)
  entries = filter(entries, "unstaged")
  if #entries == 0 then
    util.notify("Nothing to discard (discard applies to unstaged changes)")
    return
  end
  local cfg = config.get()
  if cfg.confirm_discard then
    local names = {}
    for i, entry in ipairs(entries) do
      if i > 5 then
        names[#names + 1] = string.format("… and %d more", #entries - 5)
        break
      end
      names[#names + 1] = entry.relpath
    end
    local msg = "Discard changes to:\n" .. table.concat(names, "\n")
    if not util.confirm(msg) then
      return
    end
  end
  local ok, err = git.discard(root, entries)
  after(ok, err, string.format("Discarded %d file(s)", #entries))
end

function M.stage_all(root, entries)
  M.stage(root, filter(entries, "unstaged"))
end

function M.unstage_all(root, entries)
  M.unstage(root, filter(entries, "staged"))
end

function M.discard_all(root, entries)
  entries = filter(entries, "unstaged")
  if #entries == 0 then
    util.notify("Nothing to discard")
    return
  end
  local cfg = config.get()
  if cfg.confirm_discard_all and not util.confirm(string.format("Discard all %d unstaged change(s)?", #entries)) then
    return
  end
  local ok, err = git.discard(root, entries)
  after(ok, err, "Discarded all unstaged changes")
end

function M.commit(root, staged_count, unstaged_count, on_done)
  local function finish(ok, err, msg)
    after(ok, err, msg)
    if on_done then
      on_done()
    end
  end

  local function ask(prompt)
    vim.ui.input({ prompt = prompt }, function(message)
      if message == nil then
        return
      end
      local ok, err = git.commit(root, message)
      finish(ok, err, "Committed")
    end)
  end

  if staged_count == 0 then
    if unstaged_count == 0 then
      util.notify("Nothing to commit")
      return
    end
    local cfg = config.get()
    if cfg.commit_confirm_stage_all then
      if not util.confirm("No staged changes. Stage all and commit?") then
        return
      end
    end
    local entries = select(1, git.status(root))
    if not entries then
      util.notify("Unable to read git status", vim.log.levels.ERROR)
      return
    end
    local ok, err = git.stage(root, paths(filter(entries, "unstaged")))
    if not ok then
      util.notify(err or "Failed to stage", vim.log.levels.ERROR)
      return
    end
    git.fire_git_event()
  end

  ask("Commit message: ")
end

return M
