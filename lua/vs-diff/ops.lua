local actions = require("vs-diff.actions")
local commit = require("vs-diff.commit")
local render = require("vs-diff.render")

local M = {}

function M.toggle_collapsed(collapsed, node)
  if not node or not render.is_expandable(node) then
    return false
  end
  if collapsed[node.id] then
    collapsed[node.id] = nil
  else
    collapsed[node.id] = true
  end
  return true
end

---@param opts { node: table, root?: string, entries?: table, collapsed?: table, refresh: fun(), open_file?: fun(node: table) }
function M.activate(opts)
  local node = opts.node
  if not node then
    return
  end
  local extra = node.extra or {}
  local root = opts.root
  local refresh = opts.refresh or function() end

  if node.type == "commit_box" or extra.kind == "commit_box" then
    if root then
      commit.edit(root, refresh)
    end
    return
  end
  if extra.action == "generate" or extra.kind == "generate" then
    if root then
      commit.generate(root, refresh)
    end
    return
  end
  if node.type == "commit_action" or extra.kind == "commit" then
    if root then
      local staged, unstaged, conflict = commit.count_sections(opts.entries)
      commit.submit(root, staged, unstaged, refresh, { conflict = conflict })
    end
    return
  end
  if render.is_expandable(node) then
    if opts.collapsed then
      M.toggle_collapsed(opts.collapsed, node)
    end
    refresh()
    return
  end
  if node.type == "file" and extra.entry and root then
    require("vs-diff.diff").open(extra.entry, root)
  end
end

function M.stage(root, nodes, refresh)
  if not root then
    return
  end
  actions.stage(root, actions.entries_from_nodes(nodes))
  if refresh then
    refresh()
  end
end

function M.unstage(root, nodes, refresh)
  if not root then
    return
  end
  actions.unstage(root, actions.entries_from_nodes(nodes))
  if refresh then
    refresh()
  end
end

function M.discard(root, nodes, refresh)
  if not root then
    return
  end
  actions.discard(root, actions.entries_from_nodes(nodes))
  if refresh then
    refresh()
  end
end

return M
