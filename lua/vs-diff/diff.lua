local git = require("vs-diff.git")
local util = require("vs-diff.util")
local config = require("vs-diff.config")

local M = {}

local state = {
  left_win = nil,
  right_win = nil,
}

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
  local text = git.show(root, spec)
  return text
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

  -- staged
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
      pcall(vim.cmd, "diffoff")
    end)
  end
end

function M.close()
  disable_diff(state.left_win)
  disable_diff(state.right_win)
  if util.win_valid(state.left_win) then
    pcall(vim.api.nvim_win_close, state.left_win, true)
  end
  state.left_win = nil
  state.right_win = nil
end

local function ensure_pair()
  local layout = config.get().diff.layout or "vertical"
  local right_win = pick_editor_win()
  local left_win = find_marked("left")

  if not util.win_valid(right_win) then
    right_win = vim.api.nvim_get_current_win()
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
    vim.o.splitright = splitright
    vim.o.splitbelow = splitbelow
  end

  state.left_win = left_win
  state.right_win = right_win
  mark_win(left_win, "left")
  mark_win(right_win, "right")
  return left_win, right_win
end

function M.open(entry, root)
  if not entry or not root then
    return
  end
  if entry.section == "conflict" then
    local win = pick_editor_win()
    vim.api.nvim_set_current_win(win)
    vim.cmd.edit(vim.fn.fnameescape(entry.path))
    util.notify("Opened conflicted file (resolve markers in the buffer)")
    return
  end

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

  pcall(vim.api.nvim_set_option_value, "winbar", " " .. (left_label or "OLD"), { win = left_win })
  pcall(vim.api.nvim_set_option_value, "winbar", " " .. (right_label or "NEW"), { win = right_win })

  enable_diff(left_win)
  enable_diff(right_win)

  vim.api.nvim_set_current_win(right_win)
  pcall(vim.cmd, "normal! gg]c")
end

return M
