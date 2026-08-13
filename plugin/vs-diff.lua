if vim.g.loaded_vs_diff then
  return
end
vim.g.loaded_vs_diff = true

vim.api.nvim_create_user_command("VsDiff", function(opts)
  require("vs-diff").open(opts)
end, {
  nargs = "*",
  complete = function()
    return { "focus", "show", "toggle", "close" }
  end,
  desc = "Open the VS Code-style git changes tree",
})

vim.api.nvim_create_user_command("VsDiffClose", function()
  require("vs-diff").close_diff()
end, {
  desc = "Close the vs-diff side-by-side view",
})
