local vs = require("vs-diff")
local host = require("vs-diff.host")
local A = vsdiff_assert

vs.setup({ backend = "panel" })
A.eq(host.kind(), "panel")
A.is_true(not host.has_neo_tree())

local snap = require("vs-diff.snapshot")
local nodes = snap.error_nodes("Not a git repository")
A.eq(nodes[1].type, "message")
A.eq(nodes[1].name, "Not a git repository")

return 3
