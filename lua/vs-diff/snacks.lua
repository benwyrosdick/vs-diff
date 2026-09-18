local snapshot = require("vs-diff.snapshot")
local render = require("vs-diff.render")
local ops = require("vs-diff.ops")
local actions = require("vs-diff.actions")
local commit = require("vs-diff.commit")
local config = require("vs-diff.config")

local M = {}

local collapsed = {}
local setup_done = false
local explorer_hooked = false

local function get_picker()
  local ok, picker = pcall(require, "snacks.picker")
  if not ok or not picker.get then
    return nil
  end
  return picker.get({ source = "vs_diff" })[1]
end

---Close a snacks picker and its split in this tick.
---picker:close() defers layout teardown; two left sidebars then equalize
---height and leave the editor permanently half-tall.
local function close_picker_now(picker)
  if not picker or picker.closed then
    return
  end
  pcall(function()
    picker:close()
  end)
  if picker.layout and not picker.layout.closed then
    pcall(function()
      picker.layout:close()
    end)
  end
end

local function is_sidebar_picker(picker)
  if not picker or picker.closed then
    return false
  end
  if picker.opts.source == "explorer" or picker.opts.source == "vs_diff" then
    return true
  end
  local layout = picker.opts.layout or {}
  if layout.preset == "sidebar" then
    return true
  end
  local box = layout.layout
  local pos = box and box.position
  return pos == "left" or pos == "right"
end

local function close_other_sidebars()
  local ok, picker = pcall(require, "snacks.picker")
  if not ok or not picker.get then
    return
  end
  for _, p in ipairs(picker.get({ tab = true })) do
    if p.opts.source ~= "vs_diff" and is_sidebar_picker(p) then
      close_picker_now(p)
    end
  end
end

local function refresh_picker(picker)
  picker = picker or get_picker()
  if picker and picker.refresh then
    picker:refresh()
  end
end

local function snap_of(picker)
  return (picker and picker.vs_diff) or {}
end

local function nodes_from(picker, selected)
  local items = selected
  if not items then
    items = picker:selected({ fallback = true })
  end
  local nodes = {}
  for _, item in ipairs(items or {}) do
    if item and item.node then
      nodes[#nodes + 1] = item.node
    end
  end
  return nodes
end

local function finder(_opts, ctx)
  local cwd = (ctx.filter and ctx.filter.cwd) or vim.fn.getcwd()
  local snap, err = snapshot.take(cwd)
  if not snap then
    local node = snapshot.error_nodes(err)[1]
    ctx.picker.vs_diff = { root = nil, entries = {}, nodes = { node } }
    return {
      {
        text = node.name,
        vs_id = node.id,
        vs_type = "message",
        node = node,
        row = { node = node, depth = 0 },
      },
    }
  end
  ctx.picker.vs_diff = snap
  local pattern = ctx.filter and ctx.filter.pattern or ""
  local use_collapsed = (pattern ~= "") and {} or collapsed
  local rows = render.flatten(snap.nodes, use_collapsed)
  local items = {}
  for _, row in ipairs(rows) do
    local node = row.node
    local extra = node.extra or {}
    local text = node.name
    if extra.dirpath and extra.dirpath ~= "" then
      text = text .. " " .. extra.dirpath
    end
    items[#items + 1] = {
      text = text,
      file = node.path,
      vs_id = node.id,
      vs_type = node.type,
      node = node,
      row = row,
    }
  end
  return items
end

local function format(item)
  if not item.row then
    return { { item.text or "" } }
  end
  local parts, virt = render.parts(item.row, collapsed)
  local ret = {}
  for _, part in ipairs(parts) do
    ret[#ret + 1] = { part.text, part.hl }
  end
  if virt then
    ret[#ret + 1] = {
      col = 0,
      virt_text = virt,
      virt_text_pos = "right_align",
      hl_mode = "combine",
    }
  end
  return ret
end

local function with_refresh(picker)
  return function()
    refresh_picker(picker)
  end
end

local function confirm(picker, item)
  item = item or picker:current()
  if not item or not item.node then
    return
  end
  local snap = snap_of(picker)
  ops.activate({
    node = item.node,
    root = snap.root,
    entries = snap.entries,
    collapsed = collapsed,
    refresh = with_refresh(picker),
  })
end

local function open_file(picker, item)
  item = item or picker:current()
  if not item or not item.node or item.node.type ~= "file" or not item.node.path then
    confirm(picker, item)
    return
  end
  local ok = pcall(function()
    require("snacks.picker").actions.jump(picker, item)
  end)
  if not ok then
    vim.cmd.edit(vim.fn.fnameescape(item.node.path))
  end
end

local function stage(picker)
  local snap = snap_of(picker)
  ops.stage(snap.root, nodes_from(picker), with_refresh(picker))
end

local function unstage(picker)
  local snap = snap_of(picker)
  ops.unstage(snap.root, nodes_from(picker), with_refresh(picker))
end

local function discard(picker)
  local snap = snap_of(picker)
  ops.discard(snap.root, nodes_from(picker), with_refresh(picker))
end

local function stage_all(picker)
  local snap = snap_of(picker)
  if not snap.root then
    return
  end
  actions.stage_all(snap.root, snap.entries)
  refresh_picker(picker)
end

local function unstage_all(picker)
  local snap = snap_of(picker)
  if not snap.root then
    return
  end
  actions.unstage_all(snap.root, snap.entries)
  refresh_picker(picker)
end

local function discard_all(picker)
  local snap = snap_of(picker)
  if not snap.root then
    return
  end
  actions.discard_all(snap.root, snap.entries)
  refresh_picker(picker)
end

local function toggle_view(picker)
  local cfg = config.get()
  cfg.view = cfg.view == "tree" and "list" or "tree"
  refresh_picker(picker)
end

local function do_commit(picker)
  local snap = snap_of(picker)
  if not snap.root then
    return
  end
  commit.submit(snap.root, snap.staged, snap.unstaged, with_refresh(picker), {
    conflict = snap.conflict,
  })
end

local function generate(picker)
  local snap = snap_of(picker)
  if not snap.root then
    return
  end
  commit.generate(snap.root, with_refresh(picker))
end

local function close_node(picker, item)
  item = item or picker:current()
  if not item or not item.node then
    return
  end
  local node = item.node
  if render.is_expandable(node) and not collapsed[node.id] then
    collapsed[node.id] = true
    refresh_picker(picker)
    return
  end
  local parent = item.row and item.row.parent
  if parent then
    collapsed[parent.id] = true
    refresh_picker(picker)
  end
end

local function source_opts(extra)
  extra = extra or {}
  local panel = config.get().panel or {}
  local position = panel.position or "left"
  local width = panel.width or 40
  return vim.tbl_deep_extend("force", {
    source = "vs_diff",
    title = "SCM",
    finder = finder,
    format = format,
    preview = false,
    live = false,
    focus = extra.focus == false and false or "list",
    enter = extra.enter,
    auto_close = false,
    jump = { close = false },
    layout = {
      preset = "sidebar",
      preview = false,
      hidden = { "preview" },
      layout = {
        position = position,
        width = width,
        min_width = 30,
      },
    },
    matcher = {
      fuzzy = true,
      sort_empty = false,
      filename_bonus = false,
    },
    sort = { fields = { "idx" } },
    confirm = confirm,
    actions = {
      vs_diff_confirm = confirm,
      vs_diff_open = open_file,
      vs_diff_stage = stage,
      vs_diff_unstage = unstage,
      vs_diff_discard = discard,
      vs_diff_stage_all = stage_all,
      vs_diff_unstage_all = unstage_all,
      vs_diff_discard_all = discard_all,
      vs_diff_toggle_view = toggle_view,
      vs_diff_commit = do_commit,
      vs_diff_generate = generate,
      vs_diff_close_node = close_node,
      vs_diff_close_diff = function()
        require("vs-diff.diff").close()
      end,
      vs_diff_toggle_diff = function()
        require("vs-diff.diff").toggle_style()
      end,
      vs_diff_refresh = function(picker)
        refresh_picker(picker)
      end,
    },
    win = {
      input = {
        keys = {
          ["<CR>"] = { "vs_diff_confirm", mode = { "n", "i" } },
        },
      },
      list = {
        keys = {
          ["<CR>"] = "vs_diff_confirm",
          ["<2-LeftMouse>"] = "vs_diff_confirm",
          ["o"] = "vs_diff_open",
          ["s"] = { "vs_diff_stage", mode = { "n", "x" } },
          ["u"] = { "vs_diff_unstage", mode = { "n", "x" } },
          ["x"] = { "vs_diff_discard", mode = { "n", "x" } },
          ["d"] = { "vs_diff_discard", mode = { "n", "x" } },
          ["S"] = "vs_diff_stage_all",
          ["U"] = "vs_diff_unstage_all",
          ["X"] = "vs_diff_discard_all",
          ["a"] = "vs_diff_toggle_view",
          ["c"] = "vs_diff_commit",
          ["g"] = "vs_diff_generate",
          ["Q"] = "vs_diff_close_diff",
          ["D"] = "vs_diff_toggle_diff",
          ["R"] = "vs_diff_refresh",
          ["C"] = "vs_diff_close_node",
          ["q"] = "close",
        },
      },
    },
  }, extra)
end

local function hook_explorer()
  if explorer_hooked then
    return
  end
  local ok, picker = pcall(require, "snacks.picker")
  if not ok then
    return
  end
  pcall(function()
    picker.config.wrap("explorer")
  end)
  if type(picker.explorer) ~= "function" then
    return
  end
  explorer_hooked = true
  local orig = picker.explorer
  picker.explorer = function(opts)
    M.close()
    return orig(opts)
  end
end

local function open(opts)
  hook_explorer()
  close_other_sidebars()
  local snacks = require("snacks")
  return snacks.picker.pick(source_opts(opts))
end

function M.is_open()
  return get_picker() ~= nil
end

function M.focus()
  local p = get_picker()
  if p then
    p:focus("list", { show = true })
    return
  end
  open({ focus = "list" })
end

function M.show()
  local p = get_picker()
  if p then
    return
  end
  open({ focus = false, enter = false })
end

function M.close()
  close_picker_now(get_picker())
end

function M.toggle()
  if M.is_open() then
    M.close()
    return
  end
  M.focus()
end

function M.refresh()
  local p = get_picker()
  if not p then
    return
  end
  if config.get().bind_to_cwd and p.set_cwd then
    p:set_cwd(vim.fn.getcwd())
  end
  refresh_picker(p)
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true
  local ok, picker = pcall(require, "snacks.picker")
  if ok and picker.sources then
    picker.sources.vs_diff = { title = "SCM" }
  end
  hook_explorer()
end

return M
