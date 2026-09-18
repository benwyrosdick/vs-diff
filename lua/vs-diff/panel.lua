local snapshot = require("vs-diff.snapshot")
local commit = require("vs-diff.commit")
local actions = require("vs-diff.actions")
local render = require("vs-diff.render")
local config = require("vs-diff.config")
local util = require("vs-diff.util")

local M = {}

---@class vsdiff.PanelState
---@field win integer|nil
---@field buf integer|nil
---@field cwd string
---@field root string|nil
---@field width integer|nil
---@field entries vsdiff.Entry[]
---@field nodes table[]
---@field rows table[]
---@field collapsed table<string, boolean>
---@field loading boolean
---@field cursor_id string|nil
---@field cursor_line integer|nil
---@field view table|nil

---@type table<integer, vsdiff.PanelState>
local tabs = {}
local setup_done = false
local timer

local function raw_state()
  return tabs[vim.api.nvim_get_current_tabpage()]
end

local function get_state()
  local tab = vim.api.nvim_get_current_tabpage()
  local state = tabs[tab]
  if not state then
    state = {
      win = nil,
      buf = nil,
      cwd = vim.fn.getcwd(),
      root = nil,
      entries = {},
      nodes = {},
      rows = {},
      collapsed = {},
      loading = false,
    }
    tabs[tab] = state
  end
  return state
end

local function pick_editor_win(state)
  local panel_win = state and state.win
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if win ~= panel_win and not util.is_sidebar_win(win) then
      return win
    end
  end
  if util.win_valid(panel_win) then
    vim.api.nvim_set_current_win(panel_win)
  end
  local splitright = vim.o.splitright
  vim.o.splitright = true
  vim.cmd("vsplit")
  vim.o.splitright = splitright
  return vim.api.nvim_get_current_win()
end

local function current_row(state)
  state = state or raw_state()
  if not state or not util.win_valid(state.win) then
    return nil
  end
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, state.win)
  if not ok then
    return nil
  end
  return state.rows[cursor[1]]
end

local function current_node(state)
  local row = current_row(state)
  return row and row.node
end

local function selected_nodes(state)
  state = state or get_state()
  local start = vim.fn.line("v")
  local finish = vim.fn.line(".")
  if start > finish then
    start, finish = finish, start
  end
  local nodes = {}
  for i = start, finish do
    local row = state.rows[i]
    if row then
      nodes[#nodes + 1] = row.node
    end
  end
  return nodes
end

local function exit_visual()
  local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
  vim.api.nvim_feedkeys(esc, "nx", false)
end

local function save_cursor(state)
  if not util.win_valid(state.win) then
    return
  end
  local ok, cursor = pcall(vim.api.nvim_win_get_cursor, state.win)
  if not ok then
    return
  end
  local row = state.rows[cursor[1]]
  state.cursor_id = row and row.node and row.node.id or nil
  state.cursor_line = cursor[1]
  pcall(function()
    state.view = vim.api.nvim_win_call(state.win, vim.fn.winsaveview)
  end)
end

local function restore_cursor(state)
  if not util.win_valid(state.win) then
    return
  end
  local line = state.cursor_line or 1
  if state.cursor_id then
    for i, row in ipairs(state.rows) do
      if row.node.id == state.cursor_id then
        line = i
        break
      end
    end
  end
  local max = math.max(1, #state.rows)
  line = math.max(1, math.min(line, max))
  pcall(vim.api.nvim_win_set_cursor, state.win, { line, 0 })
  if state.view then
    pcall(function()
      vim.api.nvim_win_call(state.win, function()
        vim.fn.winrestview({ topline = state.view.topline, leftcol = 0 })
      end)
    end)
  end
end

local function redraw_tree(state)
  state.rows = render.flatten(state.nodes, state.collapsed)
  render.draw(state.buf, state.rows, state.collapsed)
  restore_cursor(state)
end

local function toggle_node(state, node)
  if not node or not render.is_expandable(node) then
    return
  end
  if state.collapsed[node.id] then
    state.collapsed[node.id] = nil
  else
    state.collapsed[node.id] = true
  end
  state.cursor_id = node.id
  redraw_tree(state)
end

local function paint(state)
  if state.loading then
    return
  end
  if not util.buf_valid(state.buf) or not util.win_valid(state.win) then
    return
  end
  state.loading = true
  save_cursor(state)
  local ok, err = pcall(function()
    local cwd = state.cwd or vim.fn.getcwd()
    local snap, status_err = snapshot.take(cwd)
    if not snap then
      state.root = nil
      state.entries = {}
      state.nodes = snapshot.error_nodes(status_err)
      redraw_tree(state)
      return
    end
    state.root = snap.root
    state.entries = snap.entries
    state.nodes = snap.nodes
    redraw_tree(state)
  end)
  state.loading = false
  if not ok then
    util.notify(tostring(err), vim.log.levels.ERROR)
  end
end

local function stop_timer()
  if not timer then
    return
  end
  pcall(function()
    timer:stop()
    timer:close()
  end)
  timer = nil
end

function M.refresh(opts)
  opts = opts or {}
  local function run()
    for tab, state in pairs(tabs) do
      if vim.api.nvim_tabpage_is_valid(tab) and util.win_valid(state.win) then
        if config.get().bind_to_cwd then
          state.cwd = vim.fn.getcwd()
        end
        paint(state)
      end
    end
  end
  if opts.now then
    stop_timer()
    run()
    return
  end
  stop_timer()
  timer = vim.uv.new_timer()
  timer:start(
    40,
    0,
    vim.schedule_wrap(function()
      stop_timer()
      run()
    end)
  )
end

local function activate()
  local state = get_state()
  local node = current_node(state)
  if not node then
    return
  end
  local extra = node.extra or {}
  local root = state.root
  if node.type == "commit_box" or extra.kind == "commit_box" then
    if root then
      commit.edit(root, function()
        M.refresh({ now = true })
      end)
    end
    return
  end
  if extra.action == "generate" or extra.kind == "generate" then
    if root then
      commit.generate(root, function()
        M.refresh({ now = true })
      end)
    end
    return
  end
  if node.type == "commit_action" or extra.kind == "commit" then
    if root then
      local staged, unstaged, conflict = commit.count_sections(state.entries)
      commit.submit(root, staged, unstaged, function()
        M.refresh({ now = true })
      end, { conflict = conflict })
    end
    return
  end
  if node.type == "section" or node.type == "directory" then
    toggle_node(state, node)
    return
  end
  if node.type == "file" and extra.entry and root then
    require("vs-diff.diff").open(extra.entry, root)
  end
end

local function open_file()
  local state = get_state()
  local node = current_node(state)
  if not node then
    return
  end
  if node.type == "file" and node.path then
    local win = pick_editor_win(state)
    vim.api.nvim_set_current_win(win)
    vim.cmd.edit(vim.fn.fnameescape(node.path))
    return
  end
  if render.is_expandable(node) then
    toggle_node(state, node)
  end
end

local function stage()
  local state = get_state()
  if not state.root then
    return
  end
  actions.stage(state.root, actions.entries_from_node(current_node(state)))
  M.refresh({ now = true })
end

local function unstage()
  local state = get_state()
  if not state.root then
    return
  end
  actions.unstage(state.root, actions.entries_from_node(current_node(state)))
  M.refresh({ now = true })
end

local function discard()
  local state = get_state()
  if not state.root then
    return
  end
  actions.discard(state.root, actions.entries_from_node(current_node(state)))
  M.refresh({ now = true })
end

local function stage_visual()
  local state = get_state()
  if not state.root then
    return
  end
  local nodes = selected_nodes(state)
  exit_visual()
  actions.stage(state.root, actions.entries_from_nodes(nodes))
  M.refresh({ now = true })
end

local function unstage_visual()
  local state = get_state()
  if not state.root then
    return
  end
  local nodes = selected_nodes(state)
  exit_visual()
  actions.unstage(state.root, actions.entries_from_nodes(nodes))
  M.refresh({ now = true })
end

local function discard_visual()
  local state = get_state()
  if not state.root then
    return
  end
  local nodes = selected_nodes(state)
  exit_visual()
  actions.discard(state.root, actions.entries_from_nodes(nodes))
  M.refresh({ now = true })
end

local function stage_all()
  local state = get_state()
  if not state.root then
    return
  end
  actions.stage_all(state.root, state.entries)
  M.refresh({ now = true })
end

local function unstage_all()
  local state = get_state()
  if not state.root then
    return
  end
  actions.unstage_all(state.root, state.entries)
  M.refresh({ now = true })
end

local function discard_all()
  local state = get_state()
  if not state.root then
    return
  end
  actions.discard_all(state.root, state.entries)
  M.refresh({ now = true })
end

local function toggle_view()
  local cfg = config.get()
  cfg.view = cfg.view == "tree" and "list" or "tree"
  M.refresh({ now = true })
end

local function do_commit()
  local state = get_state()
  if not state.root then
    return
  end
  local staged, unstaged, conflict = commit.count_sections(state.entries)
  commit.submit(state.root, staged, unstaged, function()
    M.refresh({ now = true })
  end, { conflict = conflict })
end

local function generate()
  local state = get_state()
  if not state.root then
    return
  end
  commit.generate(state.root, function()
    M.refresh({ now = true })
  end)
end

local function close_node()
  local state = get_state()
  local row = current_row(state)
  if not row then
    return
  end
  local node = row.node
  if render.is_expandable(node) and not state.collapsed[node.id] then
    toggle_node(state, node)
    return
  end
  if row.parent then
    state.collapsed[row.parent.id] = true
    state.cursor_id = row.parent.id
    redraw_tree(state)
  end
end

local function close_or_quit()
  if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
    vim.cmd("quit")
    return
  end
  M.close()
end

local function bind_maps(buf)
  local function map(mode, lhs, fn, desc)
    vim.keymap.set(mode, lhs, fn, {
      buffer = buf,
      nowait = true,
      silent = true,
      desc = desc,
    })
  end
  map("n", "<CR>", activate, "Open / activate")
  map("n", "<2-LeftMouse>", activate, "Open / activate")
  map("n", "o", open_file, "Open file")
  map("n", "s", stage, "Stage")
  map("v", "s", stage_visual, "Stage selection")
  map("n", "u", unstage, "Unstage")
  map("v", "u", unstage_visual, "Unstage selection")
  map("n", "x", discard, "Discard")
  map("n", "d", discard, "Discard")
  map("v", "x", discard_visual, "Discard selection")
  map("v", "d", discard_visual, "Discard selection")
  map("n", "S", stage_all, "Stage all")
  map("n", "U", unstage_all, "Unstage all")
  map("n", "X", discard_all, "Discard all")
  map("n", "a", toggle_view, "Toggle tree / list")
  map("n", "c", do_commit, "Commit / push / pull")
  map("n", "g", generate, "Generate commit message")
  map("n", "Q", function()
    require("vs-diff.diff").close()
  end, "Close diff")
  map("n", "D", function()
    require("vs-diff.diff").toggle_style()
  end, "Toggle diff style")
  map("n", "R", function()
    M.refresh({ now = true })
  end, "Refresh")
  map("n", "q", close_or_quit, "Close SCM")
  map("n", "C", close_node, "Collapse")
end

local function ensure_buf(state)
  if util.buf_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  state.buf = buf
  vim.bo[buf].filetype = "vs-diff"
  vim.bo[buf].buflisted = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].undolevels = -1
  vim.b[buf].snacks_indent = false
  pcall(
    vim.api.nvim_buf_set_name,
    buf,
    "vs-diff://SCM@" .. tostring(vim.api.nvim_get_current_tabpage())
  )
  bind_maps(buf)
  return buf
end

local function open_win(buf, state)
  local cfg = config.get().panel or {}
  local width = state.width or cfg.width or 36
  local position = cfg.position or "left"
  if position == "right" then
    vim.cmd("botright vsplit")
  else
    vim.cmd("topleft vsplit")
  end
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_win_set_width(win, width)
  vim.wo[win].winfixwidth = true
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = "no"
  vim.wo[win].foldcolumn = "0"
  vim.wo[win].statuscolumn = ""
  vim.wo[win].wrap = false
  vim.wo[win].spell = false
  vim.wo[win].list = false
  vim.wo[win].cursorline = true
  vim.wo[win].cursorcolumn = false
  vim.wo[win].colorcolumn = ""
  vim.wo[win].fillchars = "eob: "
  pcall(function()
    vim.wo[win].winfixbuf = true
  end)
  return win
end

local function ensure_open(state)
  local buf = ensure_buf(state)
  if not util.win_valid(state.win) then
    state.win = open_win(buf, state)
  end
  paint(state)
end

function M.is_open()
  local state = raw_state()
  return state ~= nil and util.win_valid(state.win)
end

function M.win()
  local state = raw_state()
  return state and state.win
end

function M.current_node()
  return current_node(get_state())
end

function M.show()
  M.setup()
  local state = get_state()
  local prev = vim.api.nvim_get_current_win()
  ensure_open(state)
  if util.win_valid(prev) and prev ~= state.win then
    vim.api.nvim_set_current_win(prev)
  end
end

function M.focus()
  M.setup()
  local state = get_state()
  ensure_open(state)
  if util.win_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
  end
end

function M.close()
  local state = raw_state()
  if not state then
    return
  end
  if util.win_valid(state.win) then
    if #vim.api.nvim_tabpage_list_wins(0) <= 1 then
      vim.cmd("quit")
      return
    end
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil
end

function M.toggle()
  M.setup()
  if M.is_open() then
    M.close()
    return
  end
  M.focus()
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true
  local group = vim.api.nvim_create_augroup("VsDiffPanel", { clear = true })

  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local closed = tonumber(args.match)
      for _, state in pairs(tabs) do
        if state.win == closed then
          state.win = nil
        end
      end
    end,
  })

  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      local state = raw_state()
      if state and util.win_valid(state.win) then
        state.width = vim.api.nvim_win_get_width(state.win)
      end
    end,
  })

  vim.api.nvim_create_autocmd("TabClosed", {
    group = group,
    callback = function()
      for tab, state in pairs(tabs) do
        if not vim.api.nvim_tabpage_is_valid(tab) then
          if util.buf_valid(state.buf) then
            pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
          end
          tabs[tab] = nil
        end
      end
    end,
  })
end

return M
