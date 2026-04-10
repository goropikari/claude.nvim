local session = require("claude.session")

describe("session.state_dir", function()
  it("returns a path under /tmp/claude-sessions/", function()
    local dir = session.state_dir()
    assert.is_string(dir)
    assert.truthy(dir:match("^/tmp/claude%-sessions/"))
  end)

  it("replaces / and . in the servername with _", function()
    local dir = session.state_dir()
    -- key part (after the prefix) must not contain / or .
    local key = dir:sub(#"/tmp/claude-sessions/" + 1)
    assert.falsy(key:match("[/.]"))
  end)
end)

describe("session.load", function()
  local tmpdir

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
  end)

  after_each(function()
    vim.fn.delete(tmpdir, "rf")
  end)

  local function write_session(id, data)
    vim.fn.writefile({ vim.fn.json_encode(data) }, tmpdir .. "/session-" .. id .. ".json")
  end

  it("returns empty table when directory is empty", function()
    assert.same({}, session.load(tmpdir))
  end)

  it("parses a valid session file", function()
    write_session("abc123", {
      session_id = "abc123",
      status = "working",
      cwd = "/home/user/project",
      updated_at = os.time(),
    })
    local sessions = session.load(tmpdir)
    assert.is_not_nil(sessions["abc123"])
    assert.equal("working", sessions["abc123"].status)
    assert.equal("/home/user/project", sessions["abc123"].cwd)
  end)

  it("loads multiple session files", function()
    write_session("aaa", { session_id = "aaa", status = "idle", cwd = "/a", updated_at = os.time() })
    write_session("bbb", { session_id = "bbb", status = "waiting", cwd = "/b", updated_at = os.time() })
    local sessions = session.load(tmpdir)
    assert.is_not_nil(sessions["aaa"])
    assert.is_not_nil(sessions["bbb"])
  end)

  it("ignores sessions older than STALE_THRESHOLD", function()
    write_session("old", {
      session_id = "old",
      status = "idle",
      cwd = "/old",
      updated_at = os.time() - 7200, -- 2 hours ago
    })
    assert.same({}, session.load(tmpdir))
  end)

  it("ignores files with missing required fields", function()
    vim.fn.writefile({ vim.fn.json_encode({ status = "idle" }) }, tmpdir .. "/session-bad.json")
    assert.same({}, session.load(tmpdir))
  end)

  it("ignores malformed JSON without erroring", function()
    vim.fn.writefile({ "not json {{{{" }, tmpdir .. "/session-malformed.json")
    assert.same({}, session.load(tmpdir))
  end)
end)
