local config = require("vs-diff.config")

local M = {}

M.SYSTEM_PROMPT = table.concat({
  "You write git commit messages for staged diffs.",
  "Reply with the commit message only — no quotes, no markdown fences, no preamble.",
  "Do not run tools, do not edit files, do not commit.",
  "First line: imperative mood, at most 72 characters.",
  "Use a conventional commit type when it fits (feat, fix, refactor, docs, test, chore, perf).",
  "Optional body after a blank line, wrapped near 72 characters.",
  "Describe the change, not a file listing.",
}, " ")

local EXTRA_PATHS = {
  vim.fn.expand("~/.grok/bin"),
  vim.fn.expand("~/.local/bin"),
  "/opt/homebrew/bin",
  "/usr/local/bin",
}

---Ordered auto-detect list. `gh` is GitHub Copilot via `gh copilot`.
M.CLI_ORDER = { "grok", "claude", "copilot", "codex", "gemini", "llm", "gh" }

function M.clean_message(text)
  text = vim.trim(text or "")
  text = text:gsub("^```[%w_]*\r?\n", "")
  text = text:gsub("\r?\n```%s*$", "")
  text = text:gsub("^[`'\"]+", "")
  text = text:gsub("[`'\"]+$", "")
  text = vim.trim(text)
  local preamble = text:match("^[Hh]ere['’]?s?%s+[^\n]-\n%s*\n")
  if preamble then
    text = vim.trim(text:sub(#preamble + 1))
  end
  return text
end

local function parse_chat_response(body)
  local ok, decoded = pcall(vim.json.decode, body)
  if not ok or type(decoded) ~= "table" then
    return nil, body ~= "" and body or "Invalid JSON from the AI API"
  end
  if decoded.error and decoded.error.message then
    return nil, decoded.error.message
  end
  local choice = decoded.choices and decoded.choices[1]
  local content = choice and choice.message and choice.message.content
  if type(content) ~= "string" or vim.trim(content) == "" then
    return nil, "The model returned an empty commit message"
  end
  local cleaned = M.clean_message(content)
  if cleaned == "" then
    return nil, "The model returned an empty commit message"
  end
  return cleaned
end

function M.parse_chat_response(body)
  return parse_chat_response(body)
end

function M.exepath(name, extra_paths, opts)
  extra_paths = extra_paths or EXTRA_PATHS
  opts = opts or {}
  if opts.search_path ~= false then
    local found = vim.fn.exepath(name)
    if found ~= "" then
      return found
    end
  end
  for _, dir in ipairs(extra_paths) do
    local candidate = dir .. "/" .. name
    if vim.fn.executable(candidate) == 1 then
      return candidate
    end
  end
  return nil
end

function M.user_prompt(diff)
  return "Write a commit message for this staged diff:\n\n" .. diff
end

function M.full_prompt(diff)
  return M.SYSTEM_PROMPT .. "\n\n" .. M.user_prompt(diff)
end

---@class vsdiff.CliCtx
---@field file string
---@field prompt string
---@field system string
---@field exe string
---@field model string|nil

local function argv(exe, ...)
  local cmd = { exe }
  for i = 1, select("#", ...) do
    cmd[#cmd + 1] = select(i, ...)
  end
  return cmd
end

---Built-in CLI recipes. Each returns `{ cmd = string[], stdin = string|nil }`.
M.presets = {
  grok = {
    exe = "grok",
    label = "grok",
    build = function(ctx)
      return {
        cmd = argv(
          ctx.exe,
          "--prompt-file",
          ctx.file,
          "--output-format",
          "plain",
          "--verbatim",
          "--max-turns",
          "1",
          "--disable-web-search",
          "--no-subagents",
          "--permission-mode",
          "dontAsk",
          "--system-prompt-override",
          ctx.system
        ),
      }
    end,
  },
  claude = {
    exe = "claude",
    label = "claude",
    build = function(ctx)
      return {
        cmd = argv(
          ctx.exe,
          "-p",
          "--output-format",
          "text",
          "--permission-mode",
          "dontAsk",
          "--bare",
          "--system-prompt",
          ctx.system
        ),
        stdin = ctx.prompt,
      }
    end,
  },
  copilot = {
    exe = "copilot",
    label = "copilot",
    build = function(ctx)
      return {
        cmd = argv(ctx.exe, "-p", ctx.system .. "\n\n" .. ctx.prompt),
      }
    end,
  },
  gh = {
    exe = "gh",
    label = "copilot",
    build = function(ctx)
      return {
        cmd = argv(ctx.exe, "copilot", "-p", ctx.system .. "\n\n" .. ctx.prompt),
      }
    end,
  },
  codex = {
    exe = "codex",
    label = "codex",
    build = function(ctx)
      return {
        cmd = argv(ctx.exe, "exec", "--skip-git-repo-check", ctx.system .. "\n\n" .. ctx.prompt),
      }
    end,
  },
  gemini = {
    exe = "gemini",
    label = "gemini",
    build = function(ctx)
      return {
        cmd = argv(ctx.exe, "-p", ctx.system .. "\n\n" .. ctx.prompt),
      }
    end,
  },
  llm = {
    exe = "llm",
    label = "llm",
    build = function(ctx)
      local cmd = argv(ctx.exe, "-s", ctx.system)
      if ctx.model then
        cmd[#cmd + 1] = "-m"
        cmd[#cmd + 1] = ctx.model
      end
      return { cmd = cmd, stdin = ctx.prompt }
    end,
  },
}

function M.expand_placeholders(value, ctx)
  if type(value) ~= "string" then
    return value
  end
  return (
    value
      :gsub("{{file}}", ctx.file or "")
      :gsub("{{prompt}}", ctx.prompt or "")
      :gsub("{{system}}", ctx.system or "")
  )
end

function M.expand_command(command, ctx)
  if type(command) == "function" then
    return command(ctx)
  end
  if type(command) == "string" then
    return { "sh", "-c", M.expand_placeholders(command, ctx) }
  end
  if type(command) == "table" then
    local out = {}
    for _, part in ipairs(command) do
      out[#out + 1] = M.expand_placeholders(part, ctx)
    end
    return out
  end
  return nil
end

local function first_available(names, extra_paths, lookup_opts)
  for _, name in ipairs(names) do
    local path = M.exepath(name, extra_paths, lookup_opts)
    if path then
      return name, path
    end
  end
end

---@class vsdiff.ResolvedBackend
---@field kind "cli"|"api"
---@field label string
---@field name string|nil
---@field exe string|nil
---@field preset table|nil

function M.resolve(cfg, extra_paths, opts)
  cfg = cfg or config.get().ai or {}
  extra_paths = extra_paths or cfg.paths or EXTRA_PATHS
  opts = opts or {}
  local lookup_opts = { search_path = opts.search_path }
  local backend = cfg.backend or "auto"

  if type(cfg.command) == "function" or (type(cfg.command) == "table" and cfg.command[1]) or type(cfg.command) == "string" then
    if backend ~= "api" then
      return {
        kind = "cli",
        label = cfg.label or "cli",
        name = "custom",
      }
    end
  end

  local want_cli = backend == "auto" or backend == "cli" or (type(backend) == "string" and M.presets[backend])
  local cli_name = cfg.cli
  if backend ~= "auto" and backend ~= "cli" and backend ~= "api" then
    cli_name = backend
  end

  if want_cli then
    if cli_name and cli_name ~= "auto" then
      local preset = M.presets[cli_name]
      if not preset then
        return nil, string.format("Unknown AI CLI preset %q", cli_name)
      end
      local exe = M.exepath(preset.exe, extra_paths, lookup_opts)
      if not exe then
        return nil, string.format("AI CLI %q is not on PATH (%s)", cli_name, preset.exe)
      end
      return {
        kind = "cli",
        label = preset.label or cli_name,
        name = cli_name,
        exe = exe,
        preset = preset,
      }
    end

    local detected, exe = first_available(M.CLI_ORDER, extra_paths, lookup_opts)
    if detected then
      local preset = M.presets[detected]
      return {
        kind = "cli",
        label = preset.label or detected,
        name = detected,
        exe = exe,
        preset = preset,
      }
    end

    if backend == "cli" then
      return nil, "No AI CLI found (tried grok, claude, copilot, gh, codex, gemini, llm)"
    end
  end

  if backend == "auto" or backend == "api" then
    if M.api_key(cfg) then
      return { kind = "api", label = "api", name = "api" }
    end
    if backend == "api" then
      return nil, "Set XAI_API_KEY (or opts.ai.api_key) to use the HTTP API"
    end
  end

  return nil,
    "No AI backend available. Install grok/claude/copilot, or set XAI_API_KEY / opts.ai.command"
end

function M.display_name(cfg)
  local resolved = select(1, M.resolve(cfg))
  return resolved and resolved.label or nil
end

function M.api_key(cfg)
  cfg = cfg or config.get().ai or {}
  if type(cfg.api_key) == "function" then
    return cfg.api_key()
  end
  if type(cfg.api_key) == "string" and cfg.api_key ~= "" then
    return cfg.api_key
  end
  local env = cfg.env or "XAI_API_KEY"
  local value = vim.env[env]
  if value and value ~= "" then
    return value
  end
  return nil
end

local function run_api(cfg, diff, on_done)
  local key = M.api_key(cfg)
  if not key then
    on_done("Set XAI_API_KEY (or opts.ai.api_key) to generate a commit message")
    return
  end

  local payload = vim.json.encode({
    model = cfg.model or "grok-4.5",
    temperature = cfg.temperature or 0.2,
    messages = {
      { role = "system", content = M.SYSTEM_PROMPT },
      { role = "user", content = M.user_prompt(diff) },
    },
  })

  local base = (cfg.base_url or "https://api.x.ai/v1"):gsub("/$", "")
  local timeout = cfg.timeout_ms or 60000

  vim.system({
    "curl",
    "-sS",
    "-X",
    "POST",
    base .. "/chat/completions",
    "-H",
    "Authorization: Bearer " .. key,
    "-H",
    "Content-Type: application/json",
    "--max-time",
    tostring(math.ceil(timeout / 1000)),
    "-d",
    "@-",
  }, {
    text = true,
    stdin = payload,
    timeout = timeout,
  }, function(result)
    vim.schedule(function()
      if result.code ~= 0 and (not result.stdout or result.stdout == "") then
        local err = result.stderr ~= "" and result.stderr or ("curl exited " .. tostring(result.code))
        on_done(err)
        return
      end
      local message, err = parse_chat_response(result.stdout or "")
      if not message then
        on_done(err)
        return
      end
      on_done(nil, message)
    end)
  end)
end

local function finish_cli(stdout, stderr, code, tmp, on_done)
  pcall(vim.fn.delete, tmp)
  if code ~= 0 then
    local err = vim.trim((stderr or "") .. "\n" .. (stdout or ""))
    if err == "" then
      err = "AI CLI exited " .. tostring(code)
    end
    on_done(err)
    return
  end
  local message = M.clean_message(stdout or "")
  if message == "" then
    on_done("The CLI returned an empty commit message")
    return
  end
  on_done(nil, message)
end

local function run_cli(cfg, resolved, diff, root, on_done)
  local tmp = vim.fn.tempname()
  local prompt = M.user_prompt(diff)
  vim.fn.writefile(vim.split(M.full_prompt(diff), "\n", { plain = true }), tmp)

  local ctx = {
    file = tmp,
    prompt = prompt,
    system = M.SYSTEM_PROMPT,
    exe = resolved.exe,
    model = cfg.model,
    root = root,
  }

  local cmd, stdin
  if cfg.command then
    local built = M.expand_command(cfg.command, ctx)
    if type(built) == "table" and built.cmd then
      cmd, stdin = built.cmd, built.stdin
    else
      cmd = built
    end
  else
    local built = resolved.preset.build(ctx)
    cmd, stdin = built.cmd, built.stdin
  end

  if not cmd or #cmd == 0 then
    pcall(vim.fn.delete, tmp)
    on_done("AI CLI command is empty")
    return
  end

  vim.system(cmd, {
    text = true,
    stdin = stdin,
    cwd = root,
    timeout = cfg.timeout_ms or 120000,
  }, function(result)
    vim.schedule(function()
      finish_cli(result.stdout, result.stderr, result.code, tmp, on_done)
    end)
  end)
end

---Generate a commit message from a staged diff. `on_done(err, message)`.
---@param diff string
---@param on_done fun(err: string|nil, message: string|nil)
---@param opts? { root?: string }
function M.generate_commit_message(diff, on_done, opts)
  opts = opts or {}
  local cfg = config.get().ai or {}
  if cfg.enabled == false then
    on_done("AI generation is disabled (opts.ai.enabled = false)")
    return
  end
  if not diff or vim.trim(diff) == "" then
    on_done("Nothing staged — stage changes first")
    return
  end

  local max_bytes = cfg.max_diff_bytes or 80000
  if #diff > max_bytes then
    diff = diff:sub(1, max_bytes) .. "\n\n[diff truncated]"
  end

  local resolved, err = M.resolve(cfg)
  if not resolved then
    on_done(err)
    return
  end

  if resolved.kind == "api" then
    run_api(cfg, diff, on_done)
    return
  end

  run_cli(cfg, resolved, diff, opts.root, on_done)
end

return M
