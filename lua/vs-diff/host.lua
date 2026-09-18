local config = require("vs-diff.config")
local util = require("vs-diff.util")

local M = {}

local setup_done = false
local timer

local function lazy_plugin(name)
  local ok, lazy_cfg = pcall(require, "lazy.core.config")
  if not ok or not lazy_cfg.plugins then
    return nil
  end
  return lazy_cfg.plugins[name]
end

local function rtp_has(pattern)
  for _, path in ipairs(vim.api.nvim_list_runtime_paths()) do
    if path:find(pattern) then
      return true
    end
  end
  return false
end

function M.has_neo_tree()
  if package.loaded["neo-tree"] then
    return true
  end
  if vim.fn.exists(":Neotree") == 2 then
    return true
  end
  if lazy_plugin("neo-tree.nvim") then
    return true
  end
  return rtp_has("neo%-tree%.nvim") or rtp_has("/neo%-tree/")
end

function M.has_snacks()
  local ok, snacks = pcall(require, "snacks")
  return ok and snacks.picker ~= nil
end

function M.has_snacks_explorer()
  if not M.has_snacks() then
    return false
  end
  local snacks = require("snacks")
  local cfg = snacks.config.explorer
  if type(cfg) == "table" and cfg.enabled then
    return true
  end
  return vim.fn.exists("#snacks.explorer") == 1
end

---Resolved backend: "neo-tree" | "snacks" | "panel"
function M.kind()
  local want = (config.get().backend) or "auto"
  if want == "panel" then
    return "panel"
  end
  if want == "neo-tree" then
    return M.has_neo_tree() and "neo-tree" or "panel"
  end
  if want == "snacks" then
    return M.has_snacks() and "snacks" or "panel"
  end
  if M.has_neo_tree() then
    return "neo-tree"
  end
  if M.has_snacks_explorer() then
    return "snacks"
  end
  return "panel"
end

local function backend()
  local kind = M.kind()
  if kind == "snacks" then
    return require("vs-diff.snacks")
  end
  if kind == "neo-tree" then
    return require("vs-diff.neotree")
  end
  return require("vs-diff.panel")
end

function M.is_open()
  return backend().is_open()
end

function M.open(cmd_opts)
  M.setup()
  local action = vim.trim((cmd_opts and cmd_opts.args) or "")
  if action == "" then
    action = "focus"
  end
  local b = backend()
  if action == "close" then
    b.close()
  elseif action == "toggle" then
    b.toggle()
  elseif action == "show" then
    b.show()
  else
    b.focus()
  end
end

function M.refresh(opts)
  opts = opts or {}
  local function run()
    backend().refresh(opts)
  end
  if opts.now then
    if timer then
      pcall(function()
        timer:stop()
        timer:close()
      end)
      timer = nil
    end
    run()
    return
  end
  if timer then
    pcall(function()
      timer:stop()
      timer:close()
    end)
    timer = nil
  end
  timer = vim.uv.new_timer()
  timer:start(
    40,
    0,
    vim.schedule_wrap(function()
      if timer then
        pcall(function()
          timer:stop()
          timer:close()
        end)
        timer = nil
      end
      run()
    end)
  )
end

function M.setup()
  if setup_done then
    return
  end
  setup_done = true
  require("vs-diff.highlights").define()
  -- Resolve the host at open time. Snacks explorer may enable after this setup.
  if M.has_snacks() then
    pcall(function()
      require("vs-diff.snacks").setup()
    end)
  end
  if M.has_neo_tree() then
    pcall(function()
      require("vs-diff.neotree").setup()
    end)
  end
  require("vs-diff.panel").setup()

  local group = vim.api.nvim_create_augroup("VsDiffHost", { clear = true })

  vim.api.nvim_create_autocmd("ColorScheme", {
    group = group,
    callback = function()
      require("vs-diff.highlights").define()
    end,
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function(args)
      if not M.is_open() then
        return
      end
      if util.buf_valid(args.buf) and vim.bo[args.buf].buftype ~= "" then
        return
      end
      if config.get().refresh_on_write == false then
        return
      end
      M.refresh()
    end,
  })

  vim.api.nvim_create_autocmd("DirChanged", {
    group = group,
    callback = function()
      if not config.get().bind_to_cwd then
        return
      end
      if M.is_open() then
        M.refresh({ now = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd({ "FocusGained", "TermClose" }, {
    group = group,
    callback = function()
      if M.is_open() then
        M.refresh()
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "VsDiffGit", "FugitiveChanged" },
    callback = function()
      if M.is_open() then
        M.refresh()
      end
    end,
  })
end

return M
