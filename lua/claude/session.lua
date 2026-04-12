local M = {}

-- Ignore sessions whose updated_at is older than this many seconds (1 hour)
local STALE_THRESHOLD = 3600

--- @param updated_at integer|nil
--- @param now? integer
--- @return string
local function relative_age(updated_at, now)
  if type(updated_at) ~= "number" or updated_at <= 0 then
    return "unknown"
  end

  local diff = math.max(0, (now or os.time()) - updated_at)
  if diff < 60 then
    return string.format("%ds ago", diff)
  end
  if diff < 3600 then
    return string.format("%dm ago", math.floor(diff / 60))
  end
  return string.format("%dh ago", math.floor(diff / 3600))
end

--- @param updated_at integer|nil
--- @return string
local function absolute_time(updated_at)
  if type(updated_at) ~= "number" or updated_at <= 0 then
    return "unknown"
  end

  return os.date("%Y-%m-%d %H:%M:%S", updated_at)
end

--- Return the state directory for this Neovim instance.
--- Uses vim.v.servername (the NVIM socket path) as a unique key,
--- matching the $NVIM env var that terminals.nvim terminals inherit.
--- @return string
local function state_dir()
  local server = vim.v.servername
  if server and server ~= "" then
    -- Convert socket path to a safe directory name: replace / and . with _
    local key = server:gsub("[/.]", "_"):gsub("^_+", "")
    return "/tmp/claude-sessions/" .. key
  end
  return "/tmp/claude-sessions/unknown"
end

M.state_dir = state_dir
M.relative_age = relative_age
M.absolute_time = absolute_time

--- Load all active Claude Code sessions from this instance's state directory.
--- @param dir? string  Override the state directory (used in tests).
--- @return table<string, {session_id:string, status:string, cwd:string, updated_at:integer}>
function M.load(dir)
  local sessions = {}
  local pattern = (dir or state_dir()) .. "/session-*.json"
  local files = vim.fn.glob(pattern, false, true)
  local now = os.time()

  for _, path in ipairs(files) do
    local ok, lines = pcall(vim.fn.readfile, path)
    if ok and lines and lines[1] then
      local ok2, data = pcall(vim.fn.json_decode, lines[1])
      if
        ok2
        and type(data) == "table"
        and data.session_id
        and data.status
        and data.cwd
        and (now - (data.updated_at or 0)) < STALE_THRESHOLD
      then
        sessions[data.session_id] = data
      end
    end
  end

  return sessions
end

return M
