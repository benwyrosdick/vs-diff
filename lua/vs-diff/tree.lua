local util = require("vs-diff.util")

local M = {}

local SECTION_ORDER = { "conflict", "staged", "unstaged" }

local SECTION_TITLES = {
  conflict = "Merge Changes",
  staged = "Staged Changes",
  unstaged = "Changes",
}

local function sort_children(children)
  table.sort(children, function(a, b)
    if a.type ~= b.type then
      if a.type == "directory" then
        return true
      end
      if b.type == "directory" then
        return false
      end
    end
    return a.name:lower() < b.name:lower()
  end)
  for _, child in ipairs(children) do
    if child.children then
      sort_children(child.children)
    end
  end
end

local function collect_files(node, acc)
  acc = acc or {}
  if node.type == "file" then
    acc[#acc + 1] = node.extra.entry
  elseif node.children then
    for _, child in ipairs(node.children) do
      collect_files(child, acc)
    end
  end
  return acc
end

local function make_file_node(section, entry)
  return {
    id = string.format("file:%s:%s", section, entry.relpath),
    name = util.basename(entry.relpath),
    type = "file",
    path = entry.path,
    ext = entry.relpath:match("%.([^./]+)$"),
    extra = {
      kind = "file",
      section = section,
      entry = entry,
      letter = entry.letter,
      git_status = entry.xy,
    },
  }
end

local function make_list_nodes(section, entries)
  local children = {}
  for _, entry in ipairs(entries) do
    local node = make_file_node(section, entry)
    node.name = entry.relpath
    children[#children + 1] = node
  end
  table.sort(children, function(a, b)
    return a.name:lower() < b.name:lower()
  end)
  return children
end

local function make_tree_nodes(section, entries)
  local root_children = {}
  local folders = {}

  local function get_folder(rel)
    if folders[rel] then
      return folders[rel]
    end
    local name = util.basename(rel)
    local node = {
      id = string.format("dir:%s:%s", section, rel),
      name = name,
      type = "directory",
      path = rel,
      loaded = true,
      _is_expanded = true,
      children = {},
      extra = {
        kind = "folder",
        section = section,
        relpath = rel,
        entries = {},
      },
    }
    folders[rel] = node
    local parent_rel = rel:match("^(.*)/[^/]+$")
    if parent_rel then
      local parent = get_folder(parent_rel)
      parent.children[#parent.children + 1] = node
    else
      root_children[#root_children + 1] = node
    end
    return node
  end

  for _, entry in ipairs(entries) do
    local parts = util.split_relpath(entry.relpath)
    if #parts == 1 then
      root_children[#root_children + 1] = make_file_node(section, entry)
    else
      local dir_rel = table.concat(vim.list_slice(parts, 1, #parts - 1), "/")
      local folder = get_folder(dir_rel)
      folder.children[#folder.children + 1] = make_file_node(section, entry)
    end
  end

  sort_children(root_children)
  for _, folder in pairs(folders) do
    folder.extra.entries = collect_files(folder)
  end
  return root_children
end

function M.build(entries, view)
  view = view or "tree"
  local grouped = {
    conflict = {},
    staged = {},
    unstaged = {},
  }
  for _, entry in ipairs(entries or {}) do
    if grouped[entry.section] then
      grouped[entry.section][#grouped[entry.section] + 1] = entry
    end
  end

  local sections = {}
  local expanded = {}

  for _, key in ipairs(SECTION_ORDER) do
    local list = grouped[key]
    if #list > 0 then
      local children = view == "list" and make_list_nodes(key, list) or make_tree_nodes(key, list)
      local id = "section:" .. key
      expanded[#expanded + 1] = id
      local function gather_ids(nodes)
        for _, node in ipairs(nodes) do
          if node.children then
            expanded[#expanded + 1] = node.id
            gather_ids(node.children)
          end
        end
      end
      gather_ids(children)

      sections[#sections + 1] = {
        id = id,
        name = string.format("%s (%d)", SECTION_TITLES[key], #list),
        type = "section",
        loaded = true,
        _is_expanded = true,
        children = children,
        extra = {
          kind = "section",
          section = key,
          count = #list,
          entries = list,
          title = SECTION_TITLES[key],
        },
      }
    end
  end

  if #sections == 0 then
    return {
      {
        id = "message:clean",
        name = "No changes",
        type = "message",
        extra = { kind = "message" },
      },
    }, {}
  end

  return sections, expanded
end

function M.collect_entries(node)
  if not node then
    return {}
  end
  if node.extra and node.extra.entries then
    return node.extra.entries
  end
  if node.extra and node.extra.entry then
    return { node.extra.entry }
  end
  return {}
end

function M.section_titles()
  return SECTION_TITLES
end

return M
