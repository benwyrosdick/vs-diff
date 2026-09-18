.PHONY: test test-neotree
test:
	nvim --headless -u NONE --noplugin -l tests/run.lua

# Requires neo-tree.nvim, nui.nvim, and plenary.nvim in VSDIFF_TEST_DEPS
# (defaults to Neovim's data directory under lazy/).
test-neotree:
	nvim --headless -u NONE --noplugin -l tests/neotree_integration.lua
