-- Only load once
if vim.g.loaded_claude_nvim then
  return
end
vim.g.loaded_claude_nvim = true

-- Ensure hook script is executable (equivalent to chmod +x)
local _src = debug.getinfo(1, "S").source:sub(2)
local _root = _src:match("^(.+)/plugin/[^/]+$")
if _root then
  local _hook = _root .. "/scripts/hook.sh"
  if vim.uv.fs_stat(_hook) then
    vim.uv.fs_chmod(_hook, tonumber("755", 8))
  end
end

-- On exit, remove this instance's entire session directory.
vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = function()
    local dir = require("claude.session").state_dir()
    vim.fn.delete(dir, "rf")
  end,
})

vim.api.nvim_create_user_command("ClaudeStatus", function()
  require("claude").pick()
end, { desc = "Show Claude Code session status (snacks.nvim picker)" })

vim.api.nvim_create_user_command("ClaudeInstallHooks", function()
  require("claude").install_hooks()
end, { desc = "Install Claude Code hooks into ~/.claude/settings.json" })
