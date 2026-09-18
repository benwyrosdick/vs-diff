local M = {}

local LINKS = {
  VsDiffSection = "Normal",
  VsDiffSectionStaged = "DiffAdd",
  VsDiffAdded = "DiffAdd",
  VsDiffModified = "DiffChange",
  VsDiffDeleted = "DiffDelete",
  VsDiffUntracked = "DiagnosticHint",
  VsDiffRenamed = "Special",
  VsDiffConflict = "DiagnosticError",
  VsDiffCommitBox = "Title",
  VsDiffCommitPlaceholder = "Comment",
  VsDiffCommitAction = "Function",
  VsDiffGenerating = "DiagnosticInfo",
  VsDiffFilePath = "Comment",
  VsDiffDirectory = "Directory",
}

function M.define()
  for name, link in pairs(LINKS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
  vim.api.nvim_set_hl(0, "VsDiffSectionConflict", { fg = "Orange", default = true })
end

return M
