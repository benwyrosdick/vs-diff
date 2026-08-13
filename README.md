# vs-diff

A [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) source that
gives Neovim a VS Code-style Source Control view.

```
 Merge Changes (1)
    lua/conflict.lua                               C
 Staged Changes (2)
    README.md                                      M
    lua/old.lua → lua/renamed.lua                  R
 Changes (4)
   lua
     vs-diff
        git.lua                                    M
        init.lua                                   M
    scratch.txt                                    U
```

- Changes, Staged Changes, and Merge Changes as separate trees
- `<CR>` on a file opens a side-by-side diff (index ↔ worktree, or HEAD ↔ index)
- Stage / unstage / discard a file, folder, or whole section
- Works as a LazyVim plugin spec or any lazy.nvim setup

## Install (LazyVim)

Create `~/.config/nvim/lua/plugins/vs-diff.lua`:

```lua
return {
  {
    -- after you push this repo, switch `dir` to "you/vs-diff"
    dir = "~/projects/vs-diff",
    name = "vs-diff",
    dependencies = { "nvim-neo-tree/neo-tree.nvim" },
    opts = {},
    keys = {
      { "<leader>ge", "<cmd>VsDiff<cr>", desc = "Git Changes (SCM)" },
    },
  },
  {
    "nvim-neo-tree/neo-tree.nvim",
    opts = function(_, opts)
      return require("vs-diff").extend_neo_tree_opts(opts)
    end,
  },
}
```

The helper adds `vs_diff` to neo-tree `sources` and the source selector.

## Commands

| Command | Action |
| --- | --- |
| `:VsDiff` | Focus the SCM tree |
| `:VsDiff toggle` | Toggle the SCM tree |
| `:VsDiff close` | Close the SCM tree |
| `:VsDiffClose` | Close the side-by-side diff windows |

You can also run `:Neotree vs_diff`.

## Keymaps (in the tree)

| Key | Action |
| --- | --- |
| `<CR>` | Open a diff (or expand a folder / section) |
| `o` | Open the file, no diff |
| `s` | Stage file, folder, or section |
| `u` | Unstage file, folder, or section |
| `x` / `d` | Discard unstaged changes (confirms) |
| `S` / `U` / `X` | Stage / unstage / discard **all** |
| `a` | Toggle tree vs flat list |
| `c` | Commit (prompts for a message) |
| `R` | Refresh |
| `q` | Close the tree |

Visual mode `s` / `u` / `x` apply to the selection.

## Diffs

Selecting a file opens two windows next to the tree:

| Section | Left | Right |
| --- | --- | --- |
| Changes (modified) | Index | Working tree (editable) |
| Changes (untracked) | Empty | Working tree |
| Changes (deleted) | Index | Empty |
| Staged (modified) | `HEAD` | Index |
| Staged (new) | Empty | Index |
| Merge | Opens the conflicted file | |

`:VsDiffClose` tears the pair down.

## Options

```lua
require("vs-diff").setup({
  confirm_discard = true,
  confirm_discard_all = true,
  view = "tree", -- or "list"
  commit_confirm_stage_all = true,
  diff = {
    layout = "vertical", -- or "horizontal"
  },
})
```

Source-specific neo-tree options live under `vs_diff` in `neo-tree.setup()`
(mappings, renderers, `bind_to_cwd`, …).

## How it differs from neo-tree `git_status`

Built-in `git_status` is one tree of every dirty file. vs-diff splits staged vs
unstaged the way VS Code does, opens a diff instead of the file, and uses
stage / unstage / discard as the primary keys.

## Tests

```sh
nvim --headless -u NONE --noplugin -l tests/run.lua
```
