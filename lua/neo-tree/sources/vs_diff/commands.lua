local cc = require("neo-tree.sources.common.commands")
local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local utils = require("neo-tree.utils")
local git = require("vs-diff.git")
local actions = require("vs-diff.actions")
local diff = require("vs-diff.diff")
local commit = require("vs-diff.commit")
local vs_config = require("vs-diff.config")

local M = {}

local refresh = utils.wrap(manager.refresh, "vs_diff")

local function root_of(state)
  return git.root(state.path or vim.fn.getcwd())
end

local function all_entries(state)
  local entries = state.vs_diff_entries or {}
  return entries
end

local function current_node(state)
  if not state.tree then
    return nil
  end
  local ok, node = pcall(state.tree.get_node, state.tree)
  if ok then
    return node
  end
end

local function activate_commit_node(state, node)
  local extra = node.extra or {}
  local root = root_of(state)
  if not root then
    return true
  end
  if node.type == "commit_box" or extra.kind == "commit_box" then
    commit.edit(root, function()
      refresh()
    end)
    return true
  end
  if extra.action == "generate" or extra.kind == "generate" then
    commit.generate(root, refresh)
    return true
  end
  if extra.action == "commit" or extra.kind == "commit" then
    local staged, unstaged = commit.count_sections(all_entries(state))
    commit.submit(root, staged, unstaged, refresh)
    return true
  end
  return false
end

function M.open_diff(state)
  local node = current_node(state)
  if not node then
    return
  end
  if activate_commit_node(state, node) then
    return
  end
  if node.type == "section" or node.type == "directory" then
    cc.toggle_node(state)
    return
  end
  if node.type ~= "file" or not node.extra or not node.extra.entry then
    return
  end
  local root = root_of(state)
  if not root then
    return
  end
  diff.open(node.extra.entry, root)
end

function M.open(state)
  local node = current_node(state)
  if not node then
    return
  end
  if node.type == "file" and node.path then
    cc.open(state)
    return
  end
  cc.toggle_node(state)
end

function M.stage(state)
  local root = root_of(state)
  if not root then
    return
  end
  actions.stage(root, actions.entries_from_node(current_node(state)))
  refresh()
end

function M.stage_visual(state, selected_nodes)
  local root = root_of(state)
  if not root then
    return
  end
  actions.stage(root, actions.entries_from_nodes(selected_nodes))
  refresh()
end

function M.unstage(state)
  local root = root_of(state)
  if not root then
    return
  end
  actions.unstage(root, actions.entries_from_node(current_node(state)))
  refresh()
end

function M.unstage_visual(state, selected_nodes)
  local root = root_of(state)
  if not root then
    return
  end
  actions.unstage(root, actions.entries_from_nodes(selected_nodes))
  refresh()
end

function M.discard(state)
  local root = root_of(state)
  if not root then
    return
  end
  actions.discard(root, actions.entries_from_node(current_node(state)))
  refresh()
end

function M.discard_visual(state, selected_nodes)
  local root = root_of(state)
  if not root then
    return
  end
  actions.discard(root, actions.entries_from_nodes(selected_nodes))
  refresh()
end

function M.stage_all(state)
  local root = root_of(state)
  if not root then
    return
  end
  actions.stage_all(root, all_entries(state))
  refresh()
end

function M.unstage_all(state)
  local root = root_of(state)
  if not root then
    return
  end
  actions.unstage_all(root, all_entries(state))
  refresh()
end

function M.discard_all(state)
  local root = root_of(state)
  if not root then
    return
  end
  actions.discard_all(root, all_entries(state))
  refresh()
end

function M.toggle_view(state)
  local cfg = vs_config.get()
  cfg.view = cfg.view == "tree" and "list" or "tree"
  refresh()
end

function M.commit(state)
  local root = root_of(state)
  if not root then
    return
  end
  local staged, unstaged = commit.count_sections(all_entries(state))
  commit.submit(root, staged, unstaged, refresh)
end

function M.generate(state)
  local root = root_of(state)
  if not root then
    return
  end
  commit.generate(root, refresh)
end

function M.close_diff()
  require("vs-diff.diff").close()
end

function M.toggle_diff_style()
  require("vs-diff.diff").toggle_style()
end

function M.refresh(state)
  refresh()
  if state then
    renderer.redraw(state)
  end
end

cc._add_common_commands(M)

return M
