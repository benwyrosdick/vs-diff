local config = require("vs-diff.config")

local M = {}

function M.setup(opts)
  config.setup(opts)
  require("vs-diff.host").setup()
  return M
end

function M.open(cmd_opts)
  require("vs-diff.host").open(cmd_opts)
end

function M.close_diff()
  require("vs-diff.diff").close()
end

function M.refresh()
  require("vs-diff.host").refresh({ now = true })
end

---Merge vs-diff into an existing neo-tree `opts` table (LazyVim-friendly).
function M.extend_neo_tree_opts(opts)
  return require("vs-diff.neotree").extend_opts(opts)
end

---Specs for lazy.nvim / LazyVim (`lua/plugins/vs-diff.lua`).
---Pass the same fields you would put on a lazy spec (`dir`, `[1]`, `opts`, `keys`).
function M.lazy_specs(plugin_spec)
  plugin_spec = vim.deepcopy(plugin_spec or {})
  plugin_spec.name = plugin_spec.name or "vs-diff"
  plugin_spec.cmd = plugin_spec.cmd or { "VsDiff", "VsDiffClose" }
  plugin_spec.opts = plugin_spec.opts or {}
  plugin_spec.keys = plugin_spec.keys or {
    { "<leader>ge", "<cmd>VsDiff toggle<cr>", desc = "Git Changes (SCM)" },
  }
  return {
    plugin_spec,
    {
      "nvim-neo-tree/neo-tree.nvim",
      optional = true,
      opts = function(_, opts)
        return M.extend_neo_tree_opts(opts)
      end,
    },
  }
end

return M
