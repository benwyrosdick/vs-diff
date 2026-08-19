local M = {
  values = nil,
}

local defaults = {
  confirm_discard = true,
  confirm_discard_all = true,
  view = "tree", -- "tree" | "list"
  commit_confirm_stage_all = true,
  diff = {
    -- float: one snacks-style window, q dismisses (default)
    -- split: side-by-side vim diff (q closes the pair)
    style = "float", -- "float" | "split"
    layout = "vertical", -- split only: "vertical" | "horizontal"
    float = {
      width = 0.82,
      height = 0.88,
      border = "rounded",
    },
  },
  ai = {
    enabled = true,
    -- auto: first CLI on PATH (grok, claude, copilot, …), else HTTP API
    backend = "auto", -- "auto" | "cli" | "api" | "grok" | "claude" | "copilot" | "codex" | "gemini" | "llm"
    cli = "auto",
    -- Custom argv / shell string / function(ctx). Overrides presets when set.
    command = nil,
    label = nil,
    paths = nil, -- extra directories to search for CLIs
    timeout_ms = 120000,
    max_diff_bytes = 80000,
    -- HTTP fallback (SpaceXAI / xAI)
    env = "XAI_API_KEY",
    api_key = nil,
    base_url = "https://api.x.ai/v1",
    model = "grok-4.5",
    temperature = 0.2,
    effort = "low", -- grok CLI --effort / API reasoning_effort
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
