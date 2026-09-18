local git = require("vs-diff.git")
local tree = require("vs-diff.tree")
local commit = require("vs-diff.commit")
local config = require("vs-diff.config")

local M = {}

function M.error_nodes(err)
  return {
    {
      id = "message:error",
      name = err or "Not a git repository",
      type = "message",
      extra = { kind = "message" },
    },
  }
end

---@param cwd? string
---@return { root: string, entries: vsdiff.Entry[], nodes: table[], staged: integer, unstaged: integer, conflict: integer }|nil, string|nil
function M.take(cwd)
  cwd = cwd or vim.fn.getcwd()
  local entries, err, root = git.status(cwd)
  if not entries then
    return nil, err or "Not a git repository"
  end
  root = root or cwd
  local staged, unstaged, conflict = commit.count_sections(entries)
  local draft = commit.get(root)
  local remote = git.branch_status(root)
  local nodes = tree.build(entries, config.get().view, {
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
  return {
    root = root,
    entries = entries,
    nodes = nodes,
    staged = staged,
    unstaged = unstaged,
    conflict = conflict,
  }
end

return M
