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
  if node.type == "commit_box" then
    return {
      text = (config.commit_icon or "󰍩") .. " ",
      highlight = "VsDiffCommitBox",
    }
  end
  if node.type == "commit_action" then
    local extra = node.extra or {}
    if extra.action == "generate" then
      local icon = extra.generating and "" or "󰚩"
      return {
        text = icon .. " ",
        highlight = extra.generating and "VsDiffGenerating" or "VsDiffCommitAction",
      }
    end
    return {
      text = (config.commit_action_icon or "󰄬") .. " ",
      highlight = "VsDiffCommitAction",
    }
  end
  return common.icon(config, node, state)
end

M.commit_text = function(config, node, _state)
  local extra = node.extra or {}
  local highlight = "VsDiffCommitAction"
  if node.type == "commit_box" then
    highlight = extra.placeholder and "VsDiffCommitPlaceholder" or "VsDiffCommitBox"
  elseif extra.generating then
    highlight = "VsDiffGenerating"
  end
  return {
    text = node.name,
    highlight = config.highlight or highlight,
  }
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
