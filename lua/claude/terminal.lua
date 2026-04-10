local M = {}

--- Collect all loaded terminal buffers from Neovim's buffer list.
--- Uses vim.bo.channel to get the job pid, independent of terminals.nvim's
--- project-scoped state.list().
--- @return table<integer, {bufnr:integer, job_pid:integer, id:integer|nil, title:string|nil, cwd:string|nil}>
function M.get_all()
  local result = {}
  local term_state_ok, term_state = pcall(require, "terminals.state")

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].buftype == "terminal" then
      local channel = vim.bo[bufnr].channel
      if channel and channel ~= 0 then
        local ok, job_pid = pcall(vim.fn.jobpid, channel)
        if ok and job_pid and job_pid > 0 then
          -- Try to get terminals.nvim metadata (id, title, cwd) if available
          local meta = term_state_ok and term_state.find_terminal_by_bufnr(bufnr, nil) or nil
          result[bufnr] = {
            bufnr = bufnr,
            job_pid = job_pid,
            id = meta and meta.id or nil,
            title = meta and meta.title or nil,
            cwd = meta and meta.cwd or nil,
          }
        end
      end
    end
  end

  return result
end

--- Find the terminal buffer whose job_pid appears in the session's ancestor_pids list.
--- ancestor_pids is recorded by hook.sh at hook execution time (while all processes
--- are still alive), so no /proc traversal is needed at query time.
--- Falls back to cwd matching when ancestor_pids is unavailable.
--- @param terminals_map table<integer, table>
--- @param session {ancestor_pids:integer[]|nil, cwd:string}
--- @return table[]
function M.find_by_session(terminals_map, session)
  local ancestors = session.ancestor_pids

  if ancestors and #ancestors > 0 then
    local set = {}
    for _, pid in ipairs(ancestors) do
      set[pid] = true
    end
    for _, term in pairs(terminals_map) do
      if set[term.job_pid] then
        return { term }
      end
    end
    return {}
  end

  -- Fallback: cwd matching
  local matches = {}
  for _, term in pairs(terminals_map) do
    if term.cwd == session.cwd then
      table.insert(matches, term)
    end
  end
  return matches
end

return M
