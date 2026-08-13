local git = require("vs-diff.git")
local ai = require("vs-diff.ai")
local util = require("vs-diff.util")
local config = require("vs-diff.config")

local M = {}

---@class vsdiff.CommitState
---@field message string
---@field generating boolean

local drafts = {}

local function key_for(root)
  return root or vim.fn.getcwd()
end

function M.get(root)
  local key = key_for(root)
  local state = drafts[key]
  if not state then
    state = { message = "", generating = false }
    drafts[key] = state
  end
  return state
end

function M.set_message(root, message)
  local state = M.get(root)
  state.message = message or ""
  return state
end

function M.clear(root)
  local state = M.get(root)
  state.message = ""
  state.generating = false
end

function M.preview(message)
  message = vim.trim(message or "")
  if message == "" then
    return nil
  end
  local first = message:match("([^\n]*)") or message
  first = vim.trim(first)
  if vim.fn.strdisplaywidth(first) > 48 then
    first = vim.fn.strcharpart(first, 0, 45) .. "…"
  end
  return first
end

function M.count_sections(entries)
  local staged, unstaged, conflict = 0, 0, 0
  for _, entry in ipairs(entries or {}) do
    if entry.section == "staged" then
      staged = staged + 1
    elseif entry.section == "unstaged" then
      unstaged = unstaged + 1
    elseif entry.section == "conflict" then
      conflict = conflict + 1
    end
  end
  return staged, unstaged, conflict
end

local BUSY_LABELS = {
  push = "Pushing…",
  pull = "Pulling…",
  sync = "Syncing…",
  publish = "Publishing…",
}

local DONE_LABELS = {
  push = "Pushed",
  pull = "Pulled",
  sync = "Synced",
  publish = "Published branch",
}

---Decide what the primary SCM action button does.
---@param opts { staged?: integer, unstaged?: integer, conflict?: integer, ahead?: integer, behind?: integer, upstream?: string|nil, remote?: string|nil, branch?: string|nil, remote_busy?: boolean, remote_kind?: string }
---@return { action: string, label: string }
function M.primary_action(opts)
  opts = opts or {}
  if opts.remote_busy then
    local kind = opts.remote_kind
    return {
      action = kind or "commit",
      label = BUSY_LABELS[kind] or "Working…",
    }
  end

  local staged = opts.staged or 0
  local unstaged = opts.unstaged or 0
  local conflict = opts.conflict or 0
  if staged > 0 then
    return { action = "commit", label = string.format("Commit (%d)", staged) }
  end
  if unstaged > 0 or conflict > 0 then
    return { action = "commit", label = "Commit (stage all)" }
  end

  local ahead = opts.ahead or 0
  local behind = opts.behind or 0
  if ahead > 0 and behind > 0 then
    return {
      action = "sync",
      label = string.format("Sync Changes (%d↓ %d↑)", behind, ahead),
    }
  end
  if ahead > 0 then
    return { action = "push", label = string.format("Push (%d)", ahead) }
  end
  if behind > 0 then
    return { action = "pull", label = string.format("Pull (%d)", behind) }
  end
  if not opts.upstream and opts.remote and opts.branch and opts.branch ~= "HEAD" then
    return { action = "publish", label = "Publish Branch" }
  end
  return { action = "commit", label = "Commit" }
end

local function close_win(win)
  if util.win_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
end

---Open a floating gitcommit buffer. `on_done(saved_message)` after close.
function M.edit(root, on_done)
  local state = M.get(root)
  local buf = vim.api.nvim_create_buf(false, true)
  local lines = state.message == "" and { "" } or util.split_lines(state.message)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "gitcommit"
  vim.bo[buf].modifiable = true
  pcall(vim.api.nvim_buf_set_name, buf, "vs-diff://COMMIT_EDITMSG")

  local width = math.min(72, math.max(40, vim.o.columns - 8))
  local height = 10
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(1, math.floor((vim.o.lines - height) / 3)),
    col = math.max(1, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " Commit message ",
    title_pos = "center",
    zindex = 60,
  })
  vim.wo[win].wrap = true
  vim.wo[win].winhighlight = "Normal:Normal,FloatBorder:FloatBorder"

  local finished = false
  local function finish()
    if finished then
      return
    end
    finished = true
    if vim.api.nvim_buf_is_valid(buf) then
      local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
      M.set_message(root, vim.trim(text))
    end
    close_win(win)
    if on_done then
      on_done(M.get(root).message)
    end
  end

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    buffer = buf,
    once = true,
    callback = finish,
  })

  local opts = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", finish, opts)
  vim.keymap.set("n", "<Esc>", finish, opts)
  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    vim.cmd("stopinsert")
    finish()
  end, opts)
end

local function remote_args(kind, root)
  if kind == "push" then
    return { { "push" } }
  end
  if kind == "pull" then
    return { { "pull", "--no-edit" } }
  end
  if kind == "sync" then
    return { { "pull", "--no-edit" }, { "push" } }
  end
  if kind == "publish" then
    local remote = git.default_remote(root)
    if not remote then
      return nil, "No remote configured"
    end
    return { { "push", "-u", remote, "HEAD" } }
  end
  return nil, "Unknown remote action"
end

function M.run_remote(root, on_done)
  local state = M.get(root)
  if state.remote_busy then
    util.notify("Already pushing/pulling")
    return
  end

  local info, err = git.branch_status(root)
  if not info then
    util.notify(err or "Unable to read branch status", vim.log.levels.ERROR)
    return
  end

  local primary = M.primary_action({
    ahead = info.ahead,
    behind = info.behind,
    upstream = info.upstream,
    remote = info.remote,
    branch = info.branch,
  })
  local kind = primary.action
  if kind == "commit" then
    util.notify("Nothing to commit")
    return
  end

  local steps, args_err = remote_args(kind, root)
  if not steps then
    util.notify(args_err, vim.log.levels.ERROR)
    return
  end

  state.remote_busy = true
  state.remote_kind = kind
  if on_done then
    on_done()
  end
  util.notify(BUSY_LABELS[kind] or "Working…")

  local function finish(ok, msg)
    state.remote_busy = false
    state.remote_kind = nil
    if ok then
      util.notify(msg or DONE_LABELS[kind] or "Done")
      git.fire_git_event()
    else
      util.notify(msg or "git command failed", vim.log.levels.ERROR)
    end
    if on_done then
      on_done(ok)
    end
  end

  local i = 1
  local function step()
    local args = steps[i]
    git.run_async(root, args, function(ok, result)
      if not ok then
        finish(false, result)
        return
      end
      i = i + 1
      if i > #steps then
        finish(true, DONE_LABELS[kind])
        return
      end
      step()
    end)
  end
  step()
end

function M.submit(root, staged_count, unstaged_count, on_done, extra)
  extra = extra or {}
  local state = M.get(root)
  if state.remote_busy then
    util.notify("Already pushing/pulling")
    return
  end

  local conflict = extra.conflict or 0
  if staged_count == 0 and unstaged_count == 0 and conflict == 0 then
    M.run_remote(root, on_done)
    return
  end

  local message = vim.trim(state.message)

  local function do_commit(msg)
    local ok, err = git.commit(root, msg)
    if ok then
      M.clear(root)
    end
    if not ok then
      util.notify(err or "git commit failed", vim.log.levels.ERROR)
    else
      util.notify("Committed")
      git.fire_git_event()
    end
    if on_done then
      on_done(ok)
    end
  end

  local function ensure_staged(cb)
    if staged_count > 0 then
      cb()
      return
    end
    if unstaged_count == 0 then
      util.notify("Nothing to commit")
      return
    end
    if config.get().commit_confirm_stage_all then
      if not util.confirm("No staged changes. Stage all and commit?") then
        return
      end
    end
    local entries = select(1, git.status(root))
    if not entries then
      util.notify("Unable to read git status", vim.log.levels.ERROR)
      return
    end
    local paths = {}
    for _, entry in ipairs(entries) do
      if entry.section == "unstaged" then
        paths[#paths + 1] = entry.path
      end
    end
    local ok, err = git.stage(root, paths)
    if not ok then
      util.notify(err or "Failed to stage", vim.log.levels.ERROR)
      return
    end
    git.fire_git_event()
    cb()
  end

  ensure_staged(function()
    if message == "" then
      M.edit(root, function(edited)
        if not edited or vim.trim(edited) == "" then
          util.notify("Commit message is empty")
          return
        end
        do_commit(edited)
      end)
      return
    end
    do_commit(message)
  end)
end

function M.generate(root, on_refresh)
  local state = M.get(root)
  if state.generating then
    util.notify("Already generating a commit message")
    return
  end
  local diff, err = git.staged_diff(root)
  if not diff or vim.trim(diff) == "" then
    util.notify(err or "Nothing staged — stage changes first, then Generate")
    return
  end

  state.generating = true
  if on_refresh then
    on_refresh()
  end
  local label = ai.display_name()
  util.notify(label and ("Generating commit message with " .. label .. "…") or "Generating commit message…")

  ai.generate_commit_message(diff, function(gen_err, message)
    state.generating = false
    if gen_err then
      util.notify(gen_err, vim.log.levels.ERROR)
    else
      state.message = message
      util.notify(label and ("Generated with " .. label) or "Generated commit message")
    end
    if on_refresh then
      on_refresh()
    end
  end, { root = root })
end

return M
