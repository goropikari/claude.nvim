local terminal = require("claude.terminal")

local function make_term(bufnr, job_pid, cwd)
  return { bufnr = bufnr, job_pid = job_pid, cwd = cwd, id = nil, title = nil }
end

describe("terminal.find_by_session", function()
  describe("ancestor_pids matching", function()
    it("returns the terminal whose job_pid is in ancestor_pids", function()
      local term = make_term(1, 1234, "/foo")
      local result = terminal.find_by_session({ [1] = term }, {
        ancestor_pids = { 100, 1234, 200 },
        cwd = "/other",
      })
      assert.equal(1, #result)
      assert.equal(term, result[1])
    end)

    it("returns empty list when no pid matches", function()
      local term = make_term(1, 9999, "/foo")
      local result = terminal.find_by_session({ [1] = term }, {
        ancestor_pids = { 100, 200 },
        cwd = "/foo",
      })
      assert.same({}, result)
    end)

    it("does not fall back to cwd when ancestor_pids is non-empty", function()
      local term = make_term(1, 9999, "/foo")
      -- cwd matches but pid does not — should return empty, not cwd match
      local result = terminal.find_by_session({ [1] = term }, {
        ancestor_pids = { 1111 },
        cwd = "/foo",
      })
      assert.same({}, result)
    end)
  end)

  describe("cwd fallback", function()
    it("falls back to cwd when ancestor_pids is nil", function()
      local term = make_term(1, 1234, "/foo")
      local result = terminal.find_by_session({ [1] = term }, {
        ancestor_pids = nil,
        cwd = "/foo",
      })
      assert.equal(1, #result)
      assert.equal(term, result[1])
    end)

    it("falls back to cwd when ancestor_pids is empty", function()
      local term = make_term(1, 1234, "/foo")
      local result = terminal.find_by_session({ [1] = term }, {
        ancestor_pids = {},
        cwd = "/foo",
      })
      assert.equal(1, #result)
    end)

    it("returns multiple matches on cwd fallback", function()
      local terms = {
        [1] = make_term(1, 111, "/foo"),
        [2] = make_term(2, 222, "/foo"),
        [3] = make_term(3, 333, "/bar"),
      }
      local result = terminal.find_by_session(terms, { ancestor_pids = nil, cwd = "/foo" })
      assert.equal(2, #result)
    end)

    it("returns empty list when no cwd matches", function()
      local term = make_term(1, 1234, "/bar")
      local result = terminal.find_by_session({ [1] = term }, { ancestor_pids = nil, cwd = "/foo" })
      assert.same({}, result)
    end)
  end)

  it("returns empty list for empty terminals_map", function()
    local result = terminal.find_by_session({}, { ancestor_pids = { 1234 }, cwd = "/foo" })
    assert.same({}, result)
  end)
end)
