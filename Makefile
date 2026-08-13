.PHONY: test
test:
	nvim --headless -u NONE --noplugin -l tests/run.lua
