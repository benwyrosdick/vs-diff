local M = {}

function M.path_sep()
  return package.config:sub(1, 1)
end

function M.join(...)
  if vim.fs and vim.fs.joinpath then
    return vim.fs.joinpath(...)
  end
  local parts = { ... }
  local sep = M.path_sep()
  local cleaned = {}
  for _, part in ipairs(parts) do
    if part and part ~= "" then
      cleaned[#cleaned + 1] = tostring(part):gsub("[/\\]+$", "")
    end
  end
  return table.concat(cleaned, sep)
end

function M.normalize(path)
  if not path or path == "" then
    return path
  end
  if vim.fs and vim.fs.normalize then
    return vim.fs.normalize(path)
  end
  path = path:gsub("\\", "/")
  return path
end

function M.parent(path)
  path = M.normalize(path)
  local parent = path:match("^(.*)/[^/]+$")
  if parent == "" then
    return "/"
  end
  return parent
end

function M.basename(path)
  path = M.normalize(path)
  return path:match("([^/]+)$") or path
end

function M.relpath(root, path)
  root = M.normalize(root)
  path = M.normalize(path)
  if path:sub(1, #root) == root then
    local rest = path:sub(#root + 1)
    rest = rest:gsub("^/", "")
    return rest
  end
  return path
end

function M.split_relpath(relpath)
  relpath = relpath:gsub("\\", "/")
  local parts = {}
  for part in relpath:gmatch("[^/]+") do
    parts[#parts + 1] = part
  end
  return parts
end

function M.is_binary(text)
  return type(text) == "string" and text:find("\0", 1, true) ~= nil
end

function M.split_lines(text)
  if not text or text == "" then
    return {}
  end
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  if text:sub(-1) == "\n" then
    text = text:sub(1, -2)
  end
  if text == "" then
    return { "" }
  end
  return vim.split(text, "\n", { plain = true })
end

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "vs-diff" })
end

function M.confirm(msg)
  return vim.fn.confirm(msg, "&Yes\n&No", 2) == 1
end

function M.filetype(path)
  local name = M.basename(path)
  local ok, matched = pcall(vim.filetype.match, { filename = name })
  if ok and matched then
    return matched
  end
  local ext = name:match("%.([^.]+)$")
  if ext then
    return ext
  end
  return ""
end

function M.win_valid(win)
  return type(win) == "number" and win > 0 and vim.api.nvim_win_is_valid(win)
end

function M.buf_valid(buf)
  return type(buf) == "number" and buf > 0 and vim.api.nvim_buf_is_valid(buf)
end

return M
