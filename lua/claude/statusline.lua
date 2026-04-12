local M = {}

local session_mod = require("claude.session")

local _opts = {
  icons = {
    waiting = "⏳",
    working = "⚙ ",
    idle = "✓ ",
  },
  cache_ttl = 2,
}

local _cache = { counts = nil, ts = 0 }

local function refresh()
  local now = os.time()
  if _cache.counts and (now - _cache.ts) < _opts.cache_ttl then
    return _cache.counts
  end
  local counts = { waiting = 0, working = 0, idle = 0 }
  for _, sess in pairs(session_mod.load()) do
    counts[sess.status] = (counts[sess.status] or 0) + 1
  end
  _cache.counts = counts
  _cache.ts = now
  return counts
end

--- Configure the statusline module.
--- @param opts {icons?:{waiting:string,working:string,idle:string}, cache_ttl?:integer}
function M.setup(opts)
  _opts = vim.tbl_deep_extend("force", _opts, opts or {})
  M.invalidate_cache()
end

--- Invalidate the statusline cache.
function M.invalidate_cache()
  _cache = { counts = nil, ts = 0 }
end

--- Return counts per status.
--- @return {waiting:integer, working:integer, idle:integer}
function M.counts()
  return vim.deepcopy(refresh())
end

--- Return a compact summary string.
--- Zero-count statuses are omitted. Returns "" when no sessions exist.
--- Example: "⏳1 ⚙ 2"
--- @return string
function M.summary()
  local c = refresh()
  local parts = {}
  for _, key in ipairs({ "waiting", "working", "idle" }) do
    if c[key] > 0 then
      table.insert(parts, _opts.icons[key] .. c[key])
    end
  end
  return table.concat(parts, " ")
end

--- Return one icon per session, grouped by status (waiting → working → idle).
--- Example: "⏳⚙ ✓ "
--- @return string
function M.detail()
  local sessions = session_mod.load()
  local groups = { waiting = {}, working = {}, idle = {} }
  for _, sess in pairs(sessions) do
    local g = groups[sess.status]
    if g then
      table.insert(g, _opts.icons[sess.status] or "?")
    end
  end
  local out = ""
  for _, key in ipairs({ "waiting", "working", "idle" }) do
    out = out .. table.concat(groups[key])
  end
  return out
end

return M
