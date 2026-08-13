local highlights = require("neo-tree.ui.highlights")
local common = require("neo-tree.sources.common.components")

local LETTER_HL = {
  M = "VsDiffModified",
  A = "VsDiffAdded",
  D = "VsDiffDeleted",
  U = "VsDiffUntracked",
  R = "VsDiffRenamed",
  C = "VsDiffConflict",
}

local M = {}

M.section_name = function(config, node, _state)
  return {
    text = node.name,
    highlight = config.highlight or "VsDiffSection",
  }
end

M.status_letter = function(config, node, _state)
  local extra = node.extra or {}
  local letter = extra.letter
  if not letter then
    return {}
  end
  return {
    text = letter,
    highlight = config.highlight or LETTER_HL[letter] or highlights.FILE_NAME,
  }
end

M.icon = function(config, node, state)
  if node.type == "section" then
    local expanded = node:is_expanded()
    local icon = expanded and (config.expander_expanded or "") or (config.expander_collapsed or "")
    return {
      text = icon .. " ",
      highlight = config.highlight or "VsDiffSection",
    }
  end
  return common.icon(config, node, state)
end

M.name = function(config, node, state)
  if node.type == "section" then
    return M.section_name(config, node, state)
  end
  local highlight = config.highlight or highlights.FILE_NAME
  if node.type == "directory" then
    highlight = highlights.DIRECTORY_NAME
  elseif node.extra and node.extra.letter then
    highlight = LETTER_HL[node.extra.letter] or highlight
  end
  return {
    text = node.name,
    highlight = highlight,
  }
end

return vim.tbl_deep_extend("force", common, M)
