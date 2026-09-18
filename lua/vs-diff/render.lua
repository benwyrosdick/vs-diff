local config = require("vs-diff.config")

local M = {}

local NS = vim.api.nvim_create_namespace("vs-diff-tree")

local EXPANDER_OPEN = ""
local EXPANDER_CLOSED = ""

local ICONS = {
  commit_box = "󰍩",
  generate = "󰚩",
  generating = "",
  commit = "󰄬",
  push = "󰶣",
  pull = "󰶡",
  sync = "",
  publish = "󰶣",
}

local LETTER_HL = {
  M = "VsDiffModified",
  A = "VsDiffAdded",
  D = "VsDiffDeleted",
  U = "VsDiffUntracked",
  R = "VsDiffRenamed",
  C = "VsDiffConflict",
}

local SECTION_HL = {
  conflict = "VsDiffSectionConflict",
  staged = "VsDiffSectionStaged",
  unstaged = "VsDiffSection",
}

local function push(parts, text, hl)
  if not text or text == "" then
    return
  end
  parts[#parts + 1] = { text = text, hl = hl }
end

local function file_icon(node)
  local ok, MiniIcons = pcall(require, "mini.icons")
  if not ok or not MiniIcons.get then
    return nil, nil
  end
  local cat = node.type == "directory" and "directory" or "file"
  local icon, hl = MiniIcons.get(cat, node.path or node.name)
  if icon and icon ~= "" then
    return icon, hl
  end
  return nil, nil
end

function M.is_expandable(node)
  return node.type == "section" or node.type == "directory"
end

function M.is_expanded(node, collapsed)
  if not M.is_expandable(node) then
    return false
  end
  return not (collapsed and collapsed[node.id])
end

function M.flatten(nodes, collapsed)
  local rows = {}
  local function walk(node, depth, parent)
    local extra = node.extra or {}
    local parent_extra = parent and parent.extra or {}
    rows[#rows + 1] = {
      node = node,
      depth = depth,
      parent = parent,
      section = extra.section or parent_extra.section,
    }
    if M.is_expanded(node, collapsed) and node.children then
      for _, child in ipairs(node.children) do
        walk(child, depth + 1, node)
      end
    end
  end
  for _, node in ipairs(nodes or {}) do
    walk(node, 0, nil)
  end
  return rows
end

function M.parts(row, collapsed)
  local node = row.node
  local extra = node.extra or {}
  local parts = {}
  local virt
  local depth = row.depth or 0
  local section_hl = SECTION_HL[row.section or extra.section] or "VsDiffSection"

  if depth > 0 then
    push(parts, "│" .. string.rep(" ", depth * 2 - 1), section_hl)
  end

  if node.type == "commit_box" then
    local hl = "VsDiffCommitBox"
    if extra.generating then
      hl = "VsDiffGenerating"
    elseif extra.placeholder then
      hl = "VsDiffCommitPlaceholder"
    end
    push(parts, ICONS.commit_box .. " ", hl)
    push(parts, node.name, hl)
  elseif node.type == "commit_action" then
    local icon, hl
    if extra.action == "generate" then
      icon = extra.generating and ICONS.generating or ICONS.generate
      hl = extra.generating and "VsDiffGenerating" or "VsDiffCommitAction"
    else
      icon = extra.remote_busy and ICONS.generating or (ICONS[extra.action] or ICONS.commit)
      hl = extra.remote_busy and "VsDiffGenerating" or "VsDiffCommitAction"
    end
    push(parts, icon .. " ", hl)
    push(parts, node.name, hl)
  elseif node.type == "section" then
    local exp = M.is_expanded(node, collapsed) and EXPANDER_OPEN or EXPANDER_CLOSED
    push(parts, exp .. " ", section_hl)
    push(parts, node.name, section_hl)
  elseif node.type == "directory" then
    local exp = M.is_expanded(node, collapsed) and EXPANDER_OPEN or EXPANDER_CLOSED
    push(parts, exp .. " ", section_hl)
    local icon, ihl = file_icon(node)
    if icon then
      push(parts, icon .. " ", ihl or "VsDiffDirectory")
    end
    push(parts, node.name, "VsDiffDirectory")
  elseif node.type == "file" then
    local icon, ihl = file_icon(node)
    local nhl = LETTER_HL[extra.letter] or "Normal"
    if icon then
      push(parts, icon .. " ", ihl or nhl)
    end
    push(parts, node.name, nhl)
    if config.get().view == "list" and extra.dirpath and extra.dirpath ~= "" then
      push(parts, " " .. extra.dirpath, "VsDiffFilePath")
    end
    if extra.letter then
      virt = { { extra.letter, LETTER_HL[extra.letter] or "Normal" } }
    end
  else
    push(parts, node.name, "Comment")
  end

  return parts, virt
end

function M.format_row(row, collapsed)
  local parts, virt = M.parts(row, collapsed)
  local line = ""
  local marks = {}
  for _, part in ipairs(parts) do
    local start = #line
    line = line .. part.text
    if part.hl then
      marks[#marks + 1] = { col = start, end_col = #line, hl = part.hl }
    end
  end
  return line, marks, virt
end

function M.lines(nodes, collapsed)
  local rows = M.flatten(nodes, collapsed)
  local out = {}
  for _, row in ipairs(rows) do
    out[#out + 1] = (M.format_row(row, collapsed))
  end
  return out, rows
end

function M.draw(buf, rows, collapsed)
  local lines = {}
  local all_marks = {}
  local all_virt = {}
  for i, row in ipairs(rows) do
    local line, marks, virt = M.format_row(row, collapsed)
    lines[i] = line
    all_marks[i] = marks
    all_virt[i] = virt
  end
  if #lines == 0 then
    lines = { "No changes" }
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  for i, marks in ipairs(all_marks) do
    for _, mark in ipairs(marks or {}) do
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, mark.col, {
        end_col = mark.end_col,
        hl_group = mark.hl,
      })
    end
    if all_virt[i] then
      pcall(vim.api.nvim_buf_set_extmark, buf, NS, i - 1, 0, {
        virt_text = all_virt[i],
        virt_text_pos = "right_align",
      })
    end
  end
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false
end

return M
