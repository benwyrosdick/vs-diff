# vs-diff

A VS Code-style Source Control panel for Neovim.

```
󰍩 Message
󰚩 Generate
󰄬 Commit (2)
 Merge Changes (1)
│ lua/conflict.lua                                 C
 Staged Changes (2)
│ README.md                                        M
│ lua/old.lua → lua/renamed.lua                    R
 Unstaged Changes (4)
│  lua
│    vs-diff
│     git.lua                                      M
│     init.lua                                     M
│ scratch.txt                                      U
```

- Unstaged Changes, Staged Changes (always shown while dirty, even at 0), and Merge Changes as separate trees
- Commit box at the top of the tree, plus **Generate** (AI) and **Commit** (becomes Push / Pull / Sync when clean)
- `<CR>` on a file opens a side-by-side diff (index ↔ worktree, or HEAD ↔ index)
- Stage / unstage / discard a file, folder, or whole section
- Works as a LazyVim plugin spec or any lazy.nvim setup
- Hosts itself in **neo-tree** or **Snacks explorer** when those are present, otherwise uses a built-in sidebar

## Install (LazyVim)

Create `~/.config/nvim/lua/plugins/vs-diff.lua`:

```lua
return {
  {
    "benwyrosdick/vs-diff",
    opts = {},
    keys = {
      { "<leader>ge", "<cmd>VsDiff toggle<cr>", desc = "Git Changes (SCM)" },
    },
  },
}
```

If neo-tree is installed, add this so vs-diff registers as a source:

```lua
{
  "nvim-neo-tree/neo-tree.nvim",
  optional = true,
  opts = function(_, opts)
    return require("vs-diff").extend_neo_tree_opts(opts)
  end,
}
```

For local development, use `dir` instead of the GitHub spec:

```lua
{
  dir = "~/projects/vs-diff",
  name = "vs-diff",
  opts = {},
  keys = {
    { "<leader>ge", "<cmd>VsDiff toggle<cr>", desc = "Git Changes (SCM)" },
  },
}
```

## Commands

| Command | Action |
| --- | --- |
| `:VsDiff` | Focus the SCM panel |
| `:VsDiff toggle` | Toggle the SCM panel |
| `:VsDiff close` | Close the SCM panel |
| `:VsDiffClose` | Close the side-by-side diff windows |

## Keymaps (in the panel)

| Key | Action |
| --- | --- |
| `<CR>` | Open a diff, edit the commit box, or press Generate / Commit / Push / Pull |
| `D` | Toggle float vs split diff |
| `Q` | Close the current diff |
| `o` | Open the file, no diff |
| `s` | Stage file, folder, or section |
| `u` | Unstage file, folder, or section |
| `x` / `d` | Discard unstaged changes (confirms) |
| `S` / `U` / `X` | Stage / unstage / discard **all** |
| `a` | Toggle tree vs flat list |
| `g` | Generate a commit message from staged changes |
| `c` | Commit using the box (opens it if empty). Push, pull, or sync when the tree is clean |
| `R` | Refresh |
| `q` | Close the panel |

Visual mode `s` / `u` / `x` apply to the selection.

## Diffs

`<CR>` on a file opens a **single floating unified diff** (Snacks fancy renderer
when `snacks.nvim` is installed). `q` / `<Esc>` dismisses it — no leftover split.

| Style | What you get | Dismiss |
| --- | --- | --- |
| `float` (default) | One formatted inline/unified window | `q` |
| `split` | Side-by-side vim diff | `q` in either pane closes **both** |

`D` in the panel toggles float ↔ split. `Q` closes the current diff.
`:VsDiffClose` does the same.

Split mapping (when you want it):

| Section | Left | Right |
| --- | --- | --- |
| Unstaged (modified) | Index | Working tree (editable) |
| Unstaged (untracked) | Empty | Working tree |
| Unstaged (deleted) | Index | Empty |
| Staged (modified) | `HEAD` | Index |
| Staged (new) | Empty | Index |
| Merge | Opens the conflicted file | |

## Commit box

The top of the panel is a small VS Code-style commit area:

1. `<CR>` on **Message** to write or edit a draft (`<Esc>` / `q` / `<C-s>` saves)
2. `<CR>` on **Generate** (or press `g`) to draft a message from `git diff --cached`
3. `<CR>` on **Commit** (or press `c`) to commit

When there is nothing to commit, that last button follows the remote:

| State | Button | Action |
| --- | --- | --- |
| Ahead of upstream | **Push (N)** | `git push` |
| Behind upstream | **Pull (N)** | `git pull` |
| Ahead and behind | **Sync Changes (N↓ M↑)** | `git pull` then `git push` |
| No upstream, remote exists | **Publish Branch** | `git push -u <remote> HEAD` |

`c` runs the same action. Counts come from the last-fetched upstream — `R` refreshes local tracking refs, it does not fetch.

Generate prefers a CLI already on your `PATH`, in this order:

`grok` → `claude` → `copilot` → `codex` → `gemini` → `llm` → `gh copilot`

The button shows which one it picked (`Generate · grok`). Stage something first — it only looks at staged changes.

If no CLI is found, it falls back to the SpaceXAI HTTP API (`XAI_API_KEY`).

```lua
require("vs-diff").setup({
  ai = {
    backend = "auto", -- or "cli", "api", "grok", "claude", "copilot", "codex"
    -- Force one tool:
    -- backend = "claude",
    -- Or any custom command. {{file}} is a temp file with the prompt:
    -- command = { "grok", "--prompt-file", "{{file}}", "--output-format", "plain" },
  },
})
```

## Options

```lua
require("vs-diff").setup({
  confirm_discard = true,
  confirm_discard_all = true,
  view = "tree", -- or "list"
  commit_confirm_stage_all = true,
  bind_to_cwd = true,
  -- auto: neo-tree → snacks explorer → built-in panel
  backend = "auto", -- or "neo-tree", "snacks", "panel"
  panel = {
    position = "left", -- or "right"
    width = 36,
  },
  diff = {
    style = "float", -- or "split"
    layout = "vertical", -- split only
  },
  ai = {
    backend = "auto",
    env = "XAI_API_KEY",
    model = "grok-4.5",
  },
})
```

## Tests

```sh
nvim --headless -u NONE --noplugin -l tests/run.lua
```
