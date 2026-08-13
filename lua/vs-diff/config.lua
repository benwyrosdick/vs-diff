local M = {
  values = nil,
}

local defaults = {
  confirm_discard = true,
  confirm_discard_all = true,
  view = "tree", -- "tree" | "list"
  commit_confirm_stage_all = true,
  diff = {
    layout = "vertical", -- "vertical" | "horizontal"
  },
}

function M.setup(opts)
  M.values = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  return M.values
end

function M.get()
  if not M.values then
    M.setup()
  end
  return M.values
end

function M.defaults()
  return vim.deepcopy(defaults)
end

return M
