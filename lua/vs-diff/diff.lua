local git = require("vs-diff.git")
local util = require("vs-diff.util")
local config = require("vs-diff.config")

local M = {}

local NS = vim.api.nvim_create_namespace("vs-diff-inline")

local state = {
  style = nil,
  left_win = nil,
  right_win = nil,
  created_left = false,
  prev_buf = nil,
  float = nil,
  float_win = nil,
  float_buf = nil,
  last = nil, -- { entry, root }
  closing = false,
}

local function has_snacks_win()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks.win ~= nil
end

local function has_snacks_diff()
  local ok = pcall(require, "snacks.picker.util.diff")
  return ok
end

local function mark_win(win, side)
  if util.win_valid(win) then
    pcall(vim.api.nvim_win_set_var, win, "vs_diff_side", side)
  end
end

local function find_marked(side)
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    local ok, value = pcall(vim.api.nvim_win_get_var, win, "vs_diff_side")
    if ok and value == side and util.win_valid(win) then
      return win
    end
  end
end

local function is_tree_win(win)
  if not util.win_valid(win) then
    return false
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local ft = vim.bo[buf].filetype
  return ft == "neo-tree" or ft == "neo-tree-popup"
end

local function pick_editor_win()
  if util.win_valid(state.right_win) and not is_tree_win(state.right_win) then
    return state.right_win
  end
  local marked = find_marked("right")
  if marked then
    return marked
  end
  local current = vim.api.nvim_get_current_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if not is_tree_win(win) then
      return win
    end
  end
  vim.cmd("wincmd l")
  if vim.api.nvim_get_current_win() == current and is_tree_win(current) then
    vim.cmd("vsplit")
  end
  return vim.api.nvim_get_current_win()
end

local function blob_bufnr(name, text, filetype)
  local bufname = "vs-diff://" .. name
  local bufnr = vim.fn.bufnr(bufname)
  if bufnr == -1 then
    bufnr = vim.api.nvim_create_buf(false, true)
    pcall(vim.api.nvim_buf_set_name, bufnr, bufname)
  end
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "wipe"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  local lines
  if util.is_binary(text) then
    lines = { "[binary file]" }
  else
    lines = util.split_lines(text or "")
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false
  vim.bo[bufnr].readonly = true
  if filetype and filetype ~= "" then
    pcall(function()
      vim.bo[bufnr].filetype = filetype
    end)
  end
  vim.b[bufnr].vs_diff_blob = true
  return bufnr
end

local function empty_bufnr(name, filetype)
  return blob_bufnr(name, "", filetype)
end

local function show_spec(root, spec)
  return git.show(root, spec)
end

---@param entry vsdiff.Entry
---@param root string
local function sides_for(entry, root)
  local ft = util.filetype(entry.path)
  local left_buf, right_buf, left_label, right_label

  if entry.section == "unstaged" then
    if entry.kind == "untracked" then
      left_buf = empty_bufnr("empty/" .. entry.relpath, ft)
      left_label = "(new file)"
    elseif entry.kind == "deleted" then
      local text = show_spec(root, ":0:" .. entry.relpath) or show_spec(root, "HEAD:" .. entry.relpath) or ""
      left_buf = blob_bufnr("index/" .. entry.relpath, text, ft)
      left_label = "INDEX"
      right_buf = empty_bufnr("deleted/" .. entry.relpath, ft)
      right_label = "(deleted)"
      return left_buf, right_buf, left_label, right_label
    else
      local text = show_spec(root, ":0:" .. entry.relpath) or show_spec(root, "HEAD:" .. entry.relpath) or ""
      left_buf = blob_bufnr("index/" .. entry.relpath, text, ft)
      left_label = "INDEX"
    end
    return left_buf, entry.path, left_label, "WORKING TREE"
  end

  if entry.kind == "added" or (entry.kind == "renamed" and not git.has_head(root)) then
    left_buf = empty_bufnr("empty/" .. entry.relpath, ft)
    left_label = "(new file)"
  elseif entry.kind == "deleted" then
    local head_path = entry.orig_relpath or entry.relpath
    local text = show_spec(root, "HEAD:" .. head_path) or ""
    left_buf = blob_bufnr("HEAD/" .. head_path, text, ft)
    left_label = "HEAD"
    local index_text = show_spec(root, ":0:" .. entry.relpath)
    if index_text then
      right_buf = blob_bufnr("index/" .. entry.relpath, index_text, ft)
    else
      right_buf = empty_bufnr("deleted/" .. entry.relpath, ft)
    end
    return left_buf, right_buf, left_label, "INDEX"
  else
    local head_path = entry.orig_relpath or entry.relpath
    local text = show_spec(root, "HEAD:" .. head_path) or ""
    left_buf = blob_bufnr("HEAD/" .. head_path, text, ft)
    left_label = "HEAD"
  end

  local index_text = show_spec(root, ":0:" .. entry.relpath) or ""
  right_buf = blob_bufnr("index/" .. entry.relpath, index_text, ft)
  return left_buf, right_buf, left_label, "INDEX"
end

local function set_buf(win, target)
  if type(target) == "number" then
    vim.api.nvim_win_set_buf(win, target)
  else
    vim.api.nvim_set_current_win(win)
    vim.cmd.edit(vim.fn.fnameescape(target))
  end
end

local function enable_diff(win)
  vim.api.nvim_win_call(win, function()
    vim.cmd("diffthis")
    vim.wo.foldenable = false
  end)
end

local function disable_diff(win)
  if util.win_valid(win) then
    vim.api.nvim_win_call(win, function()
      pcall(vim.cmd, "diffoff!")
    end)
    pcall(vim.api.nvim_set_option_value, "winbar", "", { win = win })
  end
end

local function map_close(buf)
  if not util.buf_valid(buf) then
    return
  end
  local opts = { buffer = buf, nowait = true, silent = true, desc = "Close vs-diff" }
  vim.keymap.set("n", "q", M.close, opts)
  vim.keymap.set("n", "<Esc>", M.close, opts)
end

local function restore_editor()
  local right = state.right_win
  if not util.win_valid(right) then
    return
  end
  disable_diff(right)
  local buf = vim.api.nvim_win_get_buf(right)
  local is_blob = util.buf_valid(buf) and vim.b[buf].vs_diff_blob
  if is_blob and util.buf_valid(state.prev_buf) then
    pcall(vim.api.nvim_win_set_buf, right, state.prev_buf)
  end
end

local function close_split()
  disable_diff(state.left_win)
  restore_editor()
  if state.created_left and util.win_valid(state.left_win) then
    pcall(vim.api.nvim_win_close, state.left_win, true)
  elseif util.win_valid(state.left_win) then
    pcall(vim.api.nvim_win_close, state.left_win, true)
  end
  state.left_win = nil
  state.right_win = nil
  state.created_left = false
  state.prev_buf = nil
  pcall(vim.api.nvim_clear_autocmds, { group = "VsDiffSplit" })
end

local function close_float()
  if state.float then
    local float = state.float
    state.float = nil
    pcall(function()
      float:close()
    end)
  end
  if util.win_valid(state.float_win) then
    pcall(vim.api.nvim_win_close, state.float_win, true)
  end
  if util.buf_valid(state.float_buf) then
    pcall(vim.api.nvim_buf_delete, state.float_buf, { force = true })
  end
  state.float_win = nil
  state.float_buf = nil
end

function M.close()
  if state.closing then
    return
  end
  state.closing = true
  close_float()
  close_split()
  state.style = nil
  state.closing = false
end

local function attach_split_cleanup(left_win, right_win)
  local group = vim.api.nvim_create_augroup("VsDiffSplit", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      if state.closing then
        return
      end
      local closed = tonumber(args.match)
      if closed == left_win or closed == right_win then
        vim.schedule(M.close)
      end
    end,
  })
end

local function ensure_pair()
  local layout = config.get().diff.layout or "vertical"
  local right_win = pick_editor_win()
  local left_win = find_marked("left")
  local created_left = false

  if not util.win_valid(right_win) then
    right_win = vim.api.nvim_get_current_win()
  end

  if not state.prev_buf then
    state.prev_buf = vim.api.nvim_win_get_buf(right_win)
  end

  vim.api.nvim_set_current_win(right_win)
  disable_diff(right_win)

  if not util.win_valid(left_win) or left_win == right_win then
    local splitright = vim.o.splitright
    local splitbelow = vim.o.splitbelow
    if layout == "horizontal" then
      vim.o.splitbelow = false
      vim.cmd("split")
    else
      vim.o.splitright = false
      vim.cmd("vsplit")
    end
    left_win = vim.api.nvim_get_current_win()
    created_left = true
    vim.o.splitright = splitright
    vim.o.splitbelow = splitbelow
  end

  state.left_win = left_win
  state.right_win = right_win
  state.created_left = created_left or state.created_left
  mark_win(left_win, "left")
  mark_win(right_win, "right")
  attach_split_cleanup(left_win, right_win)
  return left_win, right_win
end

local function open_split(entry, root)
  local left_buf, right_target, left_label, right_label = sides_for(entry, root)
  if not left_buf then
    util.notify("Unable to open diff for " .. entry.relpath, vim.log.levels.ERROR)
    return
  end

  local left_win, right_win = ensure_pair()
  disable_diff(left_win)
  disable_diff(right_win)

  set_buf(left_win, left_buf)
  set_buf(right_win, right_target)

  pcall(vim.api.nvim_set_option_value, "winbar", " " .. (left_label or "OLD") .. "   q close", { win = left_win })
  pcall(vim.api.nvim_set_option_value, "winbar", " " .. (right_label or "NEW") .. "   q close", { win = right_win })

  enable_diff(left_win)
  enable_diff(right_win)

  map_close(vim.api.nvim_win_get_buf(left_win))
  map_close(vim.api.nvim_win_get_buf(right_win))

  vim.api.nvim_set_current_win(right_win)
  pcall(vim.cmd, "normal! gg]c")
end

local function title_for(entry)
  local where = entry.section == "staged" and "staged" or "working tree"
  return string.format(" %s  ·  %s ", entry.relpath, where)
end

local function fill_buf(buf, entry, root)
  local text = git.unified_diff(root, entry)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)

  if not text or vim.trim(text) == "" then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "No textual diff for " .. entry.relpath })
    vim.bo[buf].filetype = "text"
  elseif has_snacks_diff() then
    local renderer = require("snacks.picker.util.diff")
    local ok = pcall(renderer.render, buf, NS, text, {})
    if not ok then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, util.split_lines(text))
      vim.bo[buf].filetype = "diff"
    end
  else
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, util.split_lines(text))
    vim.bo[buf].filetype = "diff"
  end

  vim.bo[buf].modifiable = false
  vim.bo[buf].readonly = true
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.b[buf].vs_diff_inline = true
  map_close(buf)
end

local function open_native_float(entry, root)
  local cfg = config.get().diff.float or {}
  local width = cfg.width or 0.82
  local height = cfg.height or 0.88
  if width < 1 then
    width = math.floor(vim.o.columns * width)
  end
  if height < 1 then
    height = math.floor(vim.o.lines * height)
  end

  local buf = state.float_buf
  if not util.buf_valid(buf) then
    buf = vim.api.nvim_create_buf(false, true)
    state.float_buf = buf
  end
  fill_buf(buf, entry, root)

  if util.win_valid(state.float_win) then
    pcall(vim.api.nvim_win_set_config, state.float_win, { title = title_for(entry) })
    vim.api.nvim_set_current_win(state.float_win)
    return
  end

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = cfg.border or "rounded",
    title = title_for(entry),
    title_pos = "center",
    zindex = 50,
  })
  state.float_win = win
  vim.wo[win].wrap = false
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].cursorline = true
  vim.api.nvim_create_autocmd("WinClosed", {
    once = true,
    callback = function(args)
      if tonumber(args.match) == win then
        vim.schedule(M.close)
      end
    end,
  })
end

local function open_snacks_float(entry, root)
  local cfg = config.get().diff.float or {}
  local Snacks = require("snacks")

  local ok_valid, valid = pcall(function()
    return state.float and state.float:valid()
  end)
  if ok_valid and valid then
    fill_buf(state.float.buf, entry, root)
    pcall(function()
      state.float:set_title(title_for(entry))
    end)
    pcall(function()
      state.float:focus()
    end)
    return
  end

  local win = Snacks.win({
    show = true,
    enter = true,
    backdrop = 60,
    width = cfg.width or 0.82,
    height = cfg.height or 0.88,
    border = cfg.border or "rounded",
    title = title_for(entry),
    title_pos = "center",
    footer_keys = { "q" },
    bo = {
      buftype = "nofile",
      bufhidden = "wipe",
      swapfile = false,
      modifiable = false,
    },
    wo = {
      wrap = false,
      number = false,
      relativenumber = false,
      signcolumn = "no",
      cursorline = true,
      spell = false,
    },
    keys = {
      q = "close",
      ["<esc>"] = "close",
    },
    on_close = function()
      if not state.closing then
        state.float = nil
        vim.schedule(M.close)
      end
    end,
  })
  state.float = win
  fill_buf(win.buf, entry, root)
end

local function open_float(entry, root)
  close_split()
  if has_snacks_win() then
    local ok, err = pcall(open_snacks_float, entry, root)
    if ok then
      return
    end
    util.notify("Snacks float failed, using native: " .. tostring(err), vim.log.levels.DEBUG)
  end
  open_native_float(entry, root)
end

function M.style()
  return (config.get().diff or {}).style or "float"
end

function M.toggle_style()
  local cfg = config.get()
  cfg.diff = cfg.diff or {}
  cfg.diff.style = M.style() == "float" and "split" or "float"
  util.notify("Diff style: " .. cfg.diff.style)
  if state.last then
    M.open(state.last.entry, state.last.root)
  end
end

function M.open(entry, root)
  if not entry or not root then
    return
  end
  state.last = { entry = entry, root = root }

  if entry.section == "conflict" and M.style() == "split" then
    local win = pick_editor_win()
    vim.api.nvim_set_current_win(win)
    vim.cmd.edit(vim.fn.fnameescape(entry.path))
    util.notify("Opened conflicted file (resolve markers in the buffer)")
    return
  end

  if M.style() == "split" then
    close_float()
    open_split(entry, root)
    return
  end

  open_float(entry, root)
end

return M
