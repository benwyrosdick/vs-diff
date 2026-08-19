local ai = require("vs-diff.ai")
local commit = require("vs-diff.commit")
local tree = require("vs-diff.tree")
local A = vsdiff_assert

A.eq(ai.clean_message("feat: add box\n"), "feat: add box")
A.eq(ai.clean_message("```\nfeat: add box\n```"), "feat: add box")
A.eq(ai.clean_message("```text\nfix: newline\n```"), "fix: newline")
A.eq(ai.clean_message('"chore: quotes"'), "chore: quotes")
A.eq(ai.clean_message("Here's a commit message:\n\nfeat: hello"), "feat: hello")

local msg, err = ai.parse_chat_response(vim.json.encode({
  choices = {
    { message = { content = "```\nfeat: from api\n```" } },
  },
}))
A.eq(err, nil)
A.eq(msg, "feat: from api")

local fail_msg, fail_err = ai.parse_chat_response(vim.json.encode({
  error = { message = "Incorrect API key" },
}))
A.eq(fail_msg, nil)
A.eq(fail_err, "Incorrect API key")

A.eq(commit.preview(""), nil)
A.eq(commit.preview("feat: short"), "feat: short")
A.is_true(commit.preview(string.rep("a", 80)):find("…", 1, true) ~= nil)

local nodes = tree.commit_nodes({
  message = "",
  generating = false,
  staged = 2,
  unstaged = 1,
  generator = "grok",
})
A.eq(#nodes, 3)
A.eq(nodes[1].type, "commit_box")
A.eq(nodes[1].name, "Message")
A.eq(nodes[1].extra.placeholder, true)
A.eq(nodes[2].extra.action, "generate")
A.eq(nodes[2].name, "Generate · grok")
A.eq(nodes[3].name, "Commit (2)")

local with_draft = tree.commit_nodes({
  message = "feat: add commit box\n\nBody here",
  generating = false,
  staged = 0,
  unstaged = 3,
})
A.eq(with_draft[1].name, "feat: add commit box")
A.eq(with_draft[1].extra.placeholder, false)
A.eq(with_draft[3].name, "Commit (stage all)")

local generating = tree.commit_nodes({ message = "", generating = true, staged = 1, unstaged = 0 })
A.eq(generating[1].name, "Generating…")
A.eq(generating[2].name, "Generating…")

A.eq(commit.primary_action({ staged = 0, unstaged = 0, ahead = 2 }).action, "push")
A.eq(commit.primary_action({ staged = 0, unstaged = 0, ahead = 2 }).label, "Push (2)")
A.eq(commit.primary_action({ staged = 0, unstaged = 0, behind = 3 }).label, "Pull (3)")
A.eq(commit.primary_action({ staged = 0, unstaged = 0, ahead = 2, behind = 1 }).action, "sync")
A.eq(commit.primary_action({ staged = 0, unstaged = 0, ahead = 2, behind = 1 }).label, "Sync Changes (1↓ 2↑)")
A.eq(commit.primary_action({ staged = 0, unstaged = 0, remote = "origin", branch = "main" }).action, "publish")
A.eq(commit.primary_action({ staged = 2, ahead = 4 }).action, "commit")
A.eq(commit.primary_action({ staged = 0, unstaged = 0, conflict = 1, ahead = 2 }).action, "commit")
A.eq(commit.primary_action({ remote_busy = true, remote_kind = "push" }).label, "Pushing…")

local push_nodes = tree.commit_nodes({
  message = "",
  staged = 0,
  unstaged = 0,
  ahead = 2,
  behind = 0,
  upstream = "origin/main",
})
A.eq(push_nodes[3].name, "Push (2)")
A.eq(push_nodes[3].extra.action, "push")

local built = tree.build({}, "tree", { message = "wip", generating = false, staged = 0, unstaged = 0 })
A.eq(built[1].type, "commit_box")
A.eq(built[4].type, "message")

local ctx = { file = "/tmp/prompt.txt", prompt = "hello", system = "sys" }
A.eq(ai.expand_command({ "my-ai", "--file", "{{file}}" }, ctx), { "my-ai", "--file", "/tmp/prompt.txt" })
A.eq(ai.expand_command("run --file {{file}}", ctx), { "sh", "-c", "run --file /tmp/prompt.txt" })

local bin = vim.fn.tempname()
vim.fn.mkdir(bin, "p")
vim.fn.writefile({ "#!/bin/sh", "echo ok" }, bin .. "/claude")
vim.fn.system({ "chmod", "+x", bin .. "/claude" })
local resolved = select(1, ai.resolve({ backend = "auto" }, { bin }, { search_path = false }))
A.eq(resolved.name, "claude")
A.eq(resolved.label, "claude")
A.eq(resolved.kind, "cli")

local forced = select(1, ai.resolve({ backend = "claude" }, { bin }, { search_path = false }))
A.eq(forced.name, "claude")

local missing, missing_err = ai.resolve({ backend = "cli" }, { vim.fn.tempname() }, { search_path = false })
A.eq(missing, nil)
A.is_true(missing_err:find("No AI CLI", 1, true) ~= nil)

local grok_job = ai.presets.grok.build({
  exe = "/usr/bin/grok",
  file = "/tmp/p",
  prompt = "hello",
  system = "sys",
})
A.eq(grok_job.cmd[1], "/usr/bin/grok")
A.is_true(vim.tbl_contains(grok_job.cmd, "--prompt-file"))
A.is_true(vim.tbl_contains(grok_job.cmd, "--effort"))
local effort_i
for i, arg in ipairs(grok_job.cmd) do
  if arg == "--effort" then
    effort_i = i
  end
end
A.eq(grok_job.cmd[effort_i + 1], "low")

local claude_job = ai.presets.claude.build({
  exe = "/usr/bin/claude",
  file = "/tmp/p",
  prompt = "hello",
  system = "sys",
})
A.eq(claude_job.cmd[2], "-p")
A.eq(claude_job.stdin, "hello")

vim.fn.delete(bin, "rf")
return 30
