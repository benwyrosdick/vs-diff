local config = require("vs-diff.config")

local M = {}

function M.setup(opts)
  config.setup(opts)
  return M
end

---Merge vs-diff into an existing neo-tree `opts` table (LazyVim-friendly).
function M.extend_neo_tree_opts(opts)
  opts = opts or {}
  opts.sources = opts.sources or { "filesystem", "buffers", "git_status" }
  local found = false
  for _, source in ipairs(opts.sources) do
    if source == "vs_diff" or source == "neo-tree.sources.vs_diff" then
      found = true
      break
    end
  end
  if not found then
    opts.sources[#opts.sources + 1] = "vs_diff"
  end

  opts.source_selector = opts.source_selector or {}
  opts.source_selector.sources = opts.source_selector.sources or {}
  local selector_found = false
  for _, item in ipairs(opts.source_selector.sources) do
    if item.source == "vs_diff" then
      selector_found = true
      break
    end
  end
  if not selector_found then
    opts.source_selector.sources[#opts.source_selector.sources + 1] = {
      source = "vs_diff",
      display_name = " 󰊢 SCM ",
    }
  end
  return opts
end

---Specs for lazy.nvim / LazyVim (`lua/plugins/vs-diff.lua`).
---Pass the same fields you would put on a lazy spec (`dir`, `[1]`, `opts`, `keys`).
function M.lazy_specs(plugin_spec)
  plugin_spec = vim.deepcopy(plugin_spec or {})
  local keys = plugin_spec.keys
  local opts = plugin_spec.opts
  plugin_spec.keys = nil
  plugin_spec.opts = nil
  plugin_spec.dependencies = plugin_spec.dependencies or { "nvim-neo-tree/neo-tree.nvim" }
  plugin_spec.name = plugin_spec.name or "vs-diff"
  plugin_spec.cmd = plugin_spec.cmd or { "VsDiff", "VsDiffClose" }
  plugin_spec.opts = opts or {}
  plugin_spec.keys = keys or {
    { "<leader>ge", "<cmd>VsDiff<cr>", desc = "Git Changes (SCM)" },
  }
  return {
    plugin_spec,
    {
      "nvim-neo-tree/neo-tree.nvim",
      opts = function(_, nt_opts)
        return M.extend_neo_tree_opts(nt_opts)
      end,
    },
  }
end

function M.open(cmd_opts)
  local ok_nt, nt = pcall(require, "neo-tree")
  if not ok_nt then
    vim.notify("vs-diff requires nvim-neo-tree/neo-tree.nvim", vim.log.levels.ERROR, { title = "vs-diff" })
    return
  end
  local sources = nt.config and nt.config.sources or {}
  if not vim.tbl_contains(sources, "vs_diff") then
    vim.notify(
      'Add "vs_diff" to neo-tree sources (see require("vs-diff").extend_neo_tree_opts)',
      vim.log.levels.ERROR,
      { title = "vs-diff" }
    )
    return
  end

  local action = cmd_opts and cmd_opts.args or ""
  action = vim.trim(action)
  if action == "" then
    action = "focus"
  end
  if action == "close" then
    require("neo-tree.command").execute({ action = "close", source = "vs_diff" })
    return
  end
  require("neo-tree.command").execute({
    source = "vs_diff",
    action = action == "toggle" and "focus" or action,
    toggle = action == "toggle",
  })
end

function M.close_diff()
  require("vs-diff.diff").close()
end

return M
