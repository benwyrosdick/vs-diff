local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. package.path

local specs = {
  root .. "/tests/git_spec.lua",
  root .. "/tests/tree_spec.lua",
  root .. "/tests/git_ops_spec.lua",
  root .. "/tests/ai_spec.lua",
}

local passed, failed = 0, 0
local failures = {}

local function eq(actual, expected, msg)
  if vim.deep_equal(actual, expected) then
    return
  end
  error(string.format("%s\n  expected: %s\n  actual:   %s", msg or "values differ", vim.inspect(expected), vim.inspect(actual)), 2)
end

local function is_true(value, msg)
  if value then
    return
  end
  error(msg or "expected true", 2)
end

_G.vsdiff_assert = {
  eq = eq,
  is_true = is_true,
}

for _, spec in ipairs(specs) do
  local chunk, load_err = loadfile(spec)
  if not chunk then
    failed = failed + 1
    failures[#failures + 1] = spec .. " load error: " .. tostring(load_err)
  else
    local ok, result = pcall(chunk)
    if not ok then
      failed = failed + 1
      failures[#failures + 1] = spec .. ":\n" .. tostring(result)
    else
      passed = passed + (type(result) == "number" and result or 1)
    end
  end
end

print(string.format("vs-diff tests: %d passed, %d failed", passed, failed))
if #failures > 0 then
  print(table.concat(failures, "\n\n"))
  os.exit(1)
end
