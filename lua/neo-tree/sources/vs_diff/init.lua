local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local snapshot = require("vs-diff.snapshot")
local defaults = require("neo-tree.sources.vs_diff.defaults")

local M = {
  name = "vs_diff",
  display_name = " 󰊢 SCM ",
  default_config = defaults,
}

local function render_status(state)
  if state.loading then
    return
  end
  state.loading = true

  local cwd = state.path or vim.fn.getcwd()
  local snap, err = snapshot.take(cwd)
  if not snap then
    state.vs_diff_entries = {}
    renderer.show_nodes({
      {
        id = "message:error",
        name = err or "Not a git repository",
        type = "message",
        extra = { kind = "message" },
      },
    }, state)
    state.loading = false
    return
  end

  state.path = snap.root or cwd
  state.vs_diff_entries = snap.entries
  state.default_expanded_nodes = {}
  local function gather(nodes)
    for _, node in ipairs(nodes or {}) do
      if node.children then
        state.default_expanded_nodes[#state.default_expanded_nodes + 1] = node.id
        gather(node.children)
      end
    end
  end
  gather(snap.nodes)
  renderer.show_nodes(snap.nodes, state)
  state.loading = false
end

function M.navigate(state, path, path_to_reveal, callback)
  state.path = path or state.path or vim.fn.getcwd()
  state.dirty = false
  if path_to_reveal then
    renderer.position.set(state, path_to_reveal)
  end
  render_status(state)
  if type(callback) == "function" then
    vim.schedule(callback)
  end
end

function M.refresh()
  manager.refresh(M.name)
end

function M.setup(config, global_config)
  require("vs-diff.highlights").define()

  if config.before_render then
    manager.subscribe(M.name, {
      event = events.BEFORE_RENDER,
      handler = function(state)
        if state.name == M.name then
          config.before_render(state)
        end
      end,
    })
  end

  if global_config.enable_refresh_on_write then
    manager.subscribe(M.name, {
      event = events.VIM_BUFFER_CHANGED,
      handler = function(args)
        if utils.is_real_file(args.afile) then
          M.refresh()
        end
      end,
    })
  end

  if config.bind_to_cwd then
    manager.subscribe(M.name, {
      event = events.VIM_DIR_CHANGED,
      handler = M.refresh,
    })
  end

  manager.subscribe(M.name, {
    event = events.GIT_EVENT,
    handler = M.refresh,
  })

  manager.subscribe(M.name, {
    event = events.VIM_COLORSCHEME,
    handler = require("vs-diff.highlights").define,
  })
end

return M
