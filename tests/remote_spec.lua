local git = require("vs-diff.git")
local A = vsdiff_assert

local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

local function git_cmd(cwd, args)
  local stdout, stderr, code = git.run(cwd, args)
  if code ~= 0 then
    error(string.format("git %s failed: %s%s", table.concat(args, " "), stdout, stderr))
  end
  return stdout
end

local function write_file(cwd, rel, contents)
  local path = cwd .. "/" .. rel
  local dir = vim.fn.fnamemodify(path, ":h")
  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end
  vim.fn.writefile(vim.split(contents, "\n", { plain = true }), path)
end

local function init_ident(cwd)
  git_cmd(cwd, { "config", "user.email", "vs-diff@test.local" })
  git_cmd(cwd, { "config", "user.name", "vs-diff" })
  git_cmd(cwd, { "config", "commit.gpgsign", "false" })
end

local ok, err = pcall(function()
  local bare = tmp .. "/remote.git"
  local a = tmp .. "/a"
  local b = tmp .. "/b"
  vim.fn.mkdir(bare, "p")
  vim.fn.mkdir(a, "p")

  git_cmd(bare, { "init", "--bare", "-b", "main" })
  git_cmd(a, { "init", "-b", "main" })
  init_ident(a)
  write_file(a, "readme.txt", "one\n")
  git_cmd(a, { "add", "." })
  git_cmd(a, { "commit", "-m", "init" })
  git_cmd(a, { "remote", "add", "origin", bare })
  git_cmd(a, { "push", "-u", "origin", "main" })

  git_cmd(tmp, { "clone", bare, b })
  init_ident(b)

  write_file(a, "readme.txt", "one\ntwo\n")
  git_cmd(a, { "add", "." })
  git_cmd(a, { "commit", "-m", "ahead" })

  local status_a = assert(git.branch_status(a))
  A.eq(status_a.ahead, 1, "a is 1 commit ahead")
  A.eq(status_a.behind, 0)
  A.is_true(status_a.upstream ~= nil)

  A.is_true(select(1, git.push(a)))
  status_a = assert(git.branch_status(a))
  A.eq(status_a.ahead, 0, "push cleared ahead")

  git_cmd(b, { "fetch" })
  local status_b = assert(git.branch_status(b))
  A.eq(status_b.behind, 1, "b is 1 commit behind after fetch")
  A.is_true(select(1, git.pull(b)))
  status_b = assert(git.branch_status(b))
  A.eq(status_b.behind, 0, "pull cleared behind")
  A.eq(status_b.ahead, 0)

  write_file(a, "readme.txt", "one\ntwo\nthree\n")
  git_cmd(a, { "add", "." })
  git_cmd(a, { "commit", "-m", "from-a" })
  A.is_true(select(1, git.push(a)))

  write_file(b, "other.txt", "local\n")
  git_cmd(b, { "add", "." })
  git_cmd(b, { "commit", "-m", "from-b" })
  git_cmd(b, { "fetch" })

  status_b = assert(git.branch_status(b))
  A.eq(status_b.ahead, 1, "b is ahead after local commit")
  A.eq(status_b.behind, 1, "b is behind after a pushed")

  -- diverged: pull creates a merge, then push
  A.is_true(select(1, git.sync(b)), "sync pull+push on diverged branch")
  status_b = assert(git.branch_status(b))
  A.eq(status_b.ahead, 0)
  A.eq(status_b.behind, 0)

  local c = tmp .. "/c"
  vim.fn.mkdir(c, "p")
  git_cmd(c, { "init", "-b", "topic" })
  init_ident(c)
  write_file(c, "new.txt", "topic\n")
  git_cmd(c, { "add", "." })
  git_cmd(c, { "commit", "-m", "topic" })
  git_cmd(c, { "remote", "add", "origin", bare })
  local unpublished = assert(git.branch_status(c))
  A.eq(unpublished.upstream, nil)
  A.eq(unpublished.remote, "origin")
  A.eq(unpublished.branch, "topic")
  A.is_true(select(1, git.publish(c)))
  unpublished = assert(git.branch_status(c))
  A.is_true(unpublished.upstream ~= nil, "publish set upstream")
end)

vim.fn.delete(tmp, "rf")
if not ok then
  error(err)
end
return 8
