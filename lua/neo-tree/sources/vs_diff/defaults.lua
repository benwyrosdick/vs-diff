local config = {
  bind_to_cwd = true,
  renderers = {
    commit_box = {
      { "indent", with_markers = false },
      { "icon" },
      { "commit_text" },
    },
    commit_action = {
      { "indent", with_markers = false },
      { "icon" },
      { "commit_text" },
    },
    section = {
      { "indent" },
      { "icon" },
      { "section_name" },
    },
    directory = {
      { "indent" },
      { "icon" },
      { "name" },
    },
    file = {
      { "indent" },
      { "icon" },
      {
        "container",
        content = {
          { "name", zindex = 10 },
          { "status_letter", zindex = 20, align = "right" },
        },
      },
    },
    message = {
      { "indent", with_markers = false },
      { "name", highlight = "NeoTreeMessage" },
    },
  },
  window = {
    mappings = {
      ["<cr>"] = "open_diff",
      ["<2-LeftMouse>"] = "open_diff",
      ["o"] = "open",
      ["s"] = "stage",
      ["u"] = "unstage",
      ["x"] = "discard",
      ["d"] = "discard",
      ["S"] = "stage_all",
      ["U"] = "unstage_all",
      ["X"] = "discard_all",
      ["a"] = "toggle_view",
      ["c"] = "commit",
      ["g"] = "generate",
      ["R"] = "refresh",
      ["q"] = "close_window",
      ["A"] = "noop",
      ["T"] = "noop",
      ["r"] = "noop",
      ["y"] = "noop",
      ["p"] = "noop",
      ["m"] = "noop",
      ["C"] = "close_node",
    },
  },
}

return config
