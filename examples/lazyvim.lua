-- Drop this file into ~/.config/nvim/lua/plugins/vs-diff.lua
return {
  {
    "benwyrosdick/vs-diff",
    opts = {},
    keys = {
      { "<leader>ge", "<cmd>VsDiff toggle<cr>", desc = "Git Changes (SCM)" },
    },
  },
  -- If neo-tree is installed, register vs-diff as a source.
  {
    "nvim-neo-tree/neo-tree.nvim",
    optional = true,
    opts = function(_, opts)
      return require("vs-diff").extend_neo_tree_opts(opts)
    end,
  },
}
