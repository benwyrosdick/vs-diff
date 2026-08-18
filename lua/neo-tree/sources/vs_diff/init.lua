local manager = require("neo-tree.sources.manager")
local renderer = require("neo-tree.ui.renderer")
local events = require("neo-tree.events")
local utils = require("neo-tree.utils")
local git = require("vs-diff.git")
local tree = require("vs-diff.tree")
local commit = require("vs-diff.commit")
local vs_config = require("vs-diff.config")
local defaults = require("neo-tree.sources.vs_diff.defaults")

local M = {
  name = "vs_diff",
  display_name = " 󰊢 SCM ",
  default_config = defaults,
}

local function define_highlights()
  local links = {
    VsDiffSection = "Title",
    VsDiffAdded = "NeoTreeGitAdded",
    VsDiffModified = "NeoTreeGitModified",
    VsDiffDeleted = "NeoTreeGitDeleted",
    VsDiffUntracked = "NeoTreeGitUntracked",
    VsDiffRenamed = "NeoTreeGitRenamed",
    VsDiffConflict = "NeoTreeGitConflict",
    VsDiffCommitBox = "Title",
    VsDiffCommitPlaceholder = "Comment",
    VsDiffCommitAction = "Function",
    VsDiffGenerating = "DiagnosticInfo",
    VsDiffFilePath = "Comment",
  }
  for name, link in pairs(links) do
    if vim.fn.hlexists(name) == 0 then
      vim.api.nvim_set_hl(0, name, { link = link, default = true })
    end
  end
end

local function render_status(state)
  if state.loading then
    return
  end
  state.loading = true

  local cwd = state.path or vim.fn.getcwd()
  local entries, err, root = git.status(cwd)
  if not entries then
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

  state.path = root or cwd
  state.vs_diff_entries = entries
  local staged, unstaged, conflict = commit.count_sections(entries)
  local draft = commit.get(root)
  local remote = git.branch_status(root)
  local nodes, expanded = tree.build(entries, vs_config.get().view, {
    message = draft.message,
    generating = draft.generating,
    staged = staged,
    unstaged = unstaged,
    conflict = conflict,
    ahead = remote and remote.ahead or 0,
    behind = remote and remote.behind or 0,
    upstream = remote and remote.upstream,
    remote = remote and remote.remote,
    branch = remote and remote.branch,
    remote_busy = draft.remote_busy,
    remote_kind = draft.remote_kind,
    generator = require("vs-diff.ai").display_name(),
  })
  state.default_expanded_nodes = expanded
  renderer.show_nodes(nodes, state)
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
  define_highlights()

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
    handler = define_highlights,
  })
end

return M
