local M = {}

local session_mod = require("claude.session")
local terminal_mod = require("claude.terminal")

local STATUS_ICON = {
  waiting = { "⏳", "DiagnosticWarn" },
  working = { "⚙ ", "DiagnosticInfo" },
  idle = { "✓ ", "DiagnosticOk" },
}

--- @type {terminals: "all"|"terminals.nvim"}
local _opts = {
  terminals = "all",
}

local _watcher = nil

local function start_watcher()
  if _watcher then
    _watcher:stop()
  end

  local dir = session_mod.state_dir()
  vim.fn.mkdir(dir, "p")

  _watcher = vim.uv.new_fs_event()
  _watcher:start(
    dir,
    {},
    vim.schedule_wrap(function(err, filename, events)
      if err then
        return
      end
      require("claude.statusline").invalidate_cache()
      vim.cmd("redrawstatus")
    end)
  )
end

--- Open a snacks.nvim picker listing all known Claude Code sessions,
--- matched to terminals.nvim terminal buffers by cwd.
--- Pressing Enter jumps to the matched terminal buffer.
function M.pick()
  local sessions = session_mod.load()
  local terminals = terminal_mod.get_all()
  local items = {}
  local status_order = { waiting = 1, working = 2, idle = 3 }

  for session_id, sess in pairs(sessions) do
    local matched = terminal_mod.find_by_session(terminals, sess)

    -- In "terminals.nvim" mode, only surface terminals managed by terminals.nvim
    if _opts.terminals == "terminals.nvim" then
      local filtered = {}
      for _, term in ipairs(matched) do
        if term.id then
          table.insert(filtered, term)
        end
      end
      matched = filtered
    end

    if #matched > 0 then
      for _, term in ipairs(matched) do
        table.insert(items, {
          text = sess.cwd,
          session_id = session_id,
          status = sess.status,
          cwd = sess.cwd,
          updated_at = sess.updated_at,
          age = session_mod.relative_age(sess.updated_at),
          buf = term.bufnr,
          term_id = term.id,
          term_title = term.title,
        })
      end
    else
      table.insert(items, {
        text = sess.cwd,
        session_id = session_id,
        status = sess.status,
        cwd = sess.cwd,
        updated_at = sess.updated_at,
        age = session_mod.relative_age(sess.updated_at),
        buf = nil,
      })
    end
  end

  if #items == 0 then
    vim.notify("No active Claude Code sessions found.", vim.log.levels.INFO, { title = "ClaudeStatus" })
    return
  end

  table.sort(items, function(a, b)
    local a_status = status_order[a.status] or math.huge
    local b_status = status_order[b.status] or math.huge
    if a_status ~= b_status then
      return a_status < b_status
    end
    if a.updated_at ~= b.updated_at then
      return (a.updated_at or 0) > (b.updated_at or 0)
    end
    return a.session_id < b.session_id
  end)

  Snacks.picker({
    title = "Claude Code Sessions",
    finder = function()
      return items
    end,
    format = function(item, _picker)
      local icon_info = STATUS_ICON[item.status] or { "? ", "Comment" }
      local short_id = item.session_id:sub(1, 8)
      local bufnr_str = item.buf and (" buf:" .. item.buf) or " (no terminal)"
      return {
        { icon_info[1] .. " ", icon_info[2] },
        { vim.fn.fnamemodify(item.cwd, ":~") .. " ", "Normal" },
        { short_id .. " ", "Comment" },
        { item.age .. " ", "Directory" },
        { bufnr_str, "Special" },
      }
    end,
    preview = function(ctx)
      if ctx.item.buf and vim.api.nvim_buf_is_valid(ctx.item.buf) then
        ctx.preview:set_buf(ctx.item.buf)
      else
        ctx.preview:set_lines({
          "Session: " .. ctx.item.session_id,
          "Status:  " .. ctx.item.status,
          "Cwd:     " .. ctx.item.cwd,
          "Updated: " .. session_mod.relative_age(ctx.item.updated_at) .. " (" .. session_mod.absolute_time(
            ctx.item.updated_at
          ) .. ")",
          "Buffer:  (no terminal buffer)",
        })
      end
    end,
    confirm = function(picker)
      local item = picker:current()
      picker:close()
      if item and item.term_id then
        require("terminals.terminal").show(item.term_id)
      elseif item and item.buf and vim.api.nvim_buf_is_valid(item.buf) then
        vim.api.nvim_set_current_buf(item.buf)
      elseif item then
        vim.notify(
          "No terminal buffer for session " .. item.session_id:sub(1, 8),
          vim.log.levels.WARN,
          { title = "ClaudeStatus" }
        )
      end
    end,
  })
end

--- Write Claude Code hooks configuration to ~/.claude/settings.json.
--- Copies hook.sh to stdpath('data')/claude-nvim/hook.sh and registers that
--- stable path in the hooks config (independent of plugin install location).
function M.install_hooks()
  -- Find hook.sh in runtimepath
  local src = nil
  for _, rtp in ipairs(vim.opt.runtimepath:get()) do
    local candidate = rtp .. "/scripts/hook.sh"
    if vim.fn.filereadable(candidate) == 1 then
      src = candidate
      break
    end
  end

  if not src then
    vim.notify(
      "scripts/hook.sh not found in runtimepath. Make sure the plugin is installed.",
      vim.log.levels.ERROR,
      { title = "ClaudeInstallHooks" }
    )
    return
  end

  -- Copy to stdpath('data')/claude-nvim/hook.sh and make executable
  local dest_dir = vim.fn.stdpath("data") .. "/claude-nvim"
  vim.fn.mkdir(dest_dir, "p")
  local hook_script = dest_dir .. "/hook.sh"
  vim.fn.writefile(vim.fn.readfile(src, "b"), hook_script, "b")
  vim.uv.fs_chmod(hook_script, tonumber("755", 8))

  local settings_path = vim.fn.expand("~/.claude/settings.json")

  -- Read and parse existing settings; abort on parse failure to protect existing config
  local existing = {}
  if vim.fn.filereadable(settings_path) == 1 then
    local lines = vim.fn.readfile(settings_path)
    local raw = table.concat(lines, "\n")
    local ok, decoded = pcall(vim.fn.json_decode, raw)
    if not ok or type(decoded) ~= "table" then
      vim.notify(
        "Could not parse " .. settings_path .. " — aborting to protect existing settings.\n" .. tostring(decoded),
        vim.log.levels.ERROR,
        { title = "ClaudeInstallHooks" }
      )
      return
    end
    existing = decoded
    -- Write backup before modifying
    vim.fn.writefile(lines, settings_path .. ".bak")
  end

  -- Ensure hooks table exists
  existing.hooks = existing.hooks or {}

  local home = vim.fn.expand("~")
  local hook_path = "~" .. hook_script:sub(#home + 1)
  local hook_entry = { type = "command", command = hook_path }

  -- Notification: permission_prompt
  existing.hooks.Notification = existing.hooks.Notification or {}
  local has_notif = false
  for _, entry in ipairs(existing.hooks.Notification) do
    if entry.matcher == "permission_prompt" then
      has_notif = true
      -- Ensure our hook is present in this matcher's hooks list
      local found = false
      for _, h in ipairs(entry.hooks or {}) do
        if h.command == hook_path then
          found = true
          break
        end
      end
      if not found then
        entry.hooks = entry.hooks or {}
        table.insert(entry.hooks, hook_entry)
      end
      break
    end
  end
  if not has_notif then
    table.insert(existing.hooks.Notification, {
      matcher = "permission_prompt",
      hooks = { hook_entry },
    })
  end

  -- Stop
  existing.hooks.Stop = existing.hooks.Stop or {}
  local has_stop = false
  for _, entry in ipairs(existing.hooks.Stop) do
    for _, h in ipairs(entry.hooks or {}) do
      if h.command == hook_path then
        has_stop = true
        break
      end
    end
    if has_stop then
      break
    end
  end
  if not has_stop then
    table.insert(existing.hooks.Stop, { hooks = { hook_entry } })
  end

  -- PreToolUse
  existing.hooks.PreToolUse = existing.hooks.PreToolUse or {}
  local has_pre = false
  for _, entry in ipairs(existing.hooks.PreToolUse) do
    for _, h in ipairs(entry.hooks or {}) do
      if h.command == hook_path then
        has_pre = true
        break
      end
    end
    if has_pre then
      break
    end
  end
  if not has_pre then
    table.insert(existing.hooks.PreToolUse, { hooks = { hook_entry } })
  end

  -- SessionEnd
  existing.hooks.SessionEnd = existing.hooks.SessionEnd or {}
  local has_end = false
  for _, entry in ipairs(existing.hooks.SessionEnd) do
    for _, h in ipairs(entry.hooks or {}) do
      if h.command == hook_path then
        has_end = true
        break
      end
    end
    if has_end then
      break
    end
  end
  if not has_end then
    table.insert(existing.hooks.SessionEnd, { hooks = { hook_entry } })
  end

  -- Write back
  local json = vim.fn.json_encode(existing)
  -- Pretty-print via python3 if available, otherwise write minified
  local pretty =
    vim.fn.system({ "python3", "-c", "import sys,json; print(json.dumps(json.load(sys.stdin), indent=2))" }, json)
  local output = (vim.v.shell_error == 0 and pretty ~= "") and pretty or json

  vim.fn.mkdir(vim.fn.fnamemodify(settings_path, ":h"), "p")
  vim.fn.writefile(vim.split(output, "\n"), settings_path)

  vim.notify(
    "Hooks installed.\nhook.sh: " .. hook_script .. "\nsettings: " .. settings_path,
    vim.log.levels.INFO,
    { title = "ClaudeInstallHooks" }
  )
end

--- Plugin setup.
--- @param opts? {terminals?: "all"|"terminals.nvim", statusline?:{icons?:{waiting:string,working:string,idle:string}, cache_ttl?:integer}}
function M.setup(opts)
  opts = opts or {}
  if opts.terminals ~= nil then
    _opts.terminals = opts.terminals
  end
  if opts.statusline then
    require("claude.statusline").setup(opts.statusline)
  end
  start_watcher()
end

M.statusline_summary = function()
  return require("claude.statusline").summary()
end
M.statusline_detail = function()
  return require("claude.statusline").detail()
end
M.statusline_counts = function()
  return require("claude.statusline").counts()
end

return M
