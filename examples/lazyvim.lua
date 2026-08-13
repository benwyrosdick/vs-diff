-- Drop this file into ~/.config/nvim/lua/plugins/vs-diff.lua
return {
  {
    dir = "~/projects/vs-diff",
    name = "vs-diff",
    dependencies = { "nvim-neo-tree/neo-tree.nvim" },
    opts = {},
    keys = {
      { "<leader>ge", "<cmd>VsDiff<cr>", desc = "Git Changes (SCM)" },
    },
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = function(_, opts)
      return require("vs-diff").extend_neo_tree_opts(opts)
    end,
  },
}
