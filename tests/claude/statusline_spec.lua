-- statusline depends on claude.session at load time, so mock it before requiring.
local function load_statusline(sessions_by_id)
  package.loaded["claude.session"] = {
    load = function()
      return sessions_by_id
    end,
  }
  package.loaded["claude.statusline"] = nil
  return require("claude.statusline")
end

local function make_sess(id, status)
  return { session_id = id, status = status, cwd = "/" .. id, updated_at = os.time() }
end

describe("statusline", function()
  after_each(function()
    package.loaded["claude.session"] = nil
    package.loaded["claude.statusline"] = nil
  end)

  describe("counts", function()
    it("returns zero counts when no sessions", function()
      local sl = load_statusline({})
      assert.same({ waiting = 0, working = 0, idle = 0 }, sl.counts())
    end)

    it("counts each status correctly", function()
      local sl = load_statusline({
        a = make_sess("a", "waiting"),
        b = make_sess("b", "working"),
        c = make_sess("c", "working"),
        d = make_sess("d", "idle"),
      })
      assert.same({ waiting = 1, working = 2, idle = 1 }, sl.counts())
    end)
  end)

  describe("summary", function()
    it("returns empty string when no sessions", function()
      local sl = load_statusline({})
      assert.equal("", sl.summary())
    end)

    it("omits statuses with zero count", function()
      local sl = load_statusline({ a = make_sess("a", "working") })
      local s = sl.summary()
      assert.falsy(s:match("⏳"))
      assert.falsy(s:match("✓"))
      assert.truthy(s:match("⚙"))
    end)

    it("includes counts for non-zero statuses", function()
      local sl = load_statusline({
        a = make_sess("a", "waiting"),
        b = make_sess("b", "waiting"),
        c = make_sess("c", "idle"),
      })
      local s = sl.summary()
      assert.truthy(s:match("⏳2"))
      assert.truthy(s:match("✓ 1"))
    end)

    it("orders waiting before working before idle", function()
      local sl = load_statusline({
        a = make_sess("a", "idle"),
        b = make_sess("b", "waiting"),
        c = make_sess("c", "working"),
      })
      local s = sl.summary()
      assert.truthy(s:find("⏳") < s:find("⚙") and s:find("⚙") < s:find("✓"))
    end)
  end)

  describe("detail", function()
    it("returns empty string when no sessions", function()
      local sl = load_statusline({})
      assert.equal("", sl.detail())
    end)

    it("returns one icon per session", function()
      local sl = load_statusline({
        a = make_sess("a", "waiting"),
        b = make_sess("b", "working"),
        c = make_sess("c", "idle"),
      })
      -- Use ASCII icons to avoid multi-byte counting issues
      sl.setup({ icons = { waiting = "W", working = "K", idle = "I" } })
      assert.equal("WKI", sl.detail())
    end)

    it("repeats icon for multiple sessions of the same status", function()
      local sl = load_statusline({
        a = make_sess("a", "waiting"),
        b = make_sess("b", "waiting"),
        c = make_sess("c", "idle"),
      })
      sl.setup({ icons = { waiting = "W", working = "K", idle = "I" } })
      local s = sl.detail()
      assert.equal(2, select(2, s:gsub("W", "")))
      assert.equal(1, select(2, s:gsub("I", "")))
    end)

    it("groups waiting before idle", function()
      local sl = load_statusline({
        a = make_sess("a", "idle"),
        b = make_sess("b", "waiting"),
      })
      local s = sl.detail()
      assert.truthy(s:find("⏳") < s:find("✓"))
    end)
  end)

  describe("setup", function()
    it("custom icons appear in output", function()
      local sl = load_statusline({ a = make_sess("a", "waiting") })
      sl.setup({ icons = { waiting = "W", working = "K", idle = "I" } })
      assert.truthy(sl.summary():match("^W1$"))
    end)
  end)
end)
