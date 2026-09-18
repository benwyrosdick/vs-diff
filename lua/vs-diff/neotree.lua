local M = {}

local function nt()
  local ok, neo_tree = pcall(require, "neo-tree")
  if not ok then
    return nil
  end
  return neo_tree
end

function M.extend_opts(opts)
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

function M.setup()
  local neo_tree = nt()
  if not neo_tree then
    return
  end
  if neo_tree.config then
    M.extend_opts(neo_tree.config)
  end
end

local function execute(opts)
  M.setup()
  require("neo-tree.command").execute(opts)
  if opts.action == "focus" then
    local state = require("neo-tree.sources.manager").get_state("vs_diff")
    -- Switching sources can reuse the sidebar without entering its window.
    -- Check the rendered source as a toggle may have just closed it.
    if require("neo-tree.ui.renderer").window_exists(state) then
      vim.api.nvim_set_current_win(state.winid)
    end
  end
end

function M.is_open()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then
    return false
  end
  local ok_state, state = pcall(manager.get_state, "vs_diff")
  if not ok_state or not state then
    return false
  end
  local win = state.winid
  return type(win) == "number" and vim.api.nvim_win_is_valid(win)
end

function M.focus()
  execute({ source = "vs_diff", action = "focus" })
end

function M.show()
  execute({ source = "vs_diff", action = "show" })
end

function M.close()
  execute({ source = "vs_diff", action = "close" })
end

function M.toggle()
  execute({ source = "vs_diff", action = "focus", toggle = true })
end

function M.refresh()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if ok then
    pcall(manager.refresh, "vs_diff")
  end
end

return M
