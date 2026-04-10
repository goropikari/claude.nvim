-- Minimal init for development / smoke-testing.
-- No plugin manager. Dependencies are cloned into .dev/ by `make dev`.

local root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h")
local dev_dir = root .. "/.dev"

-- Add this plugin and its dependencies to runtimepath
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(dev_dir .. "/snacks.nvim")
vim.opt.rtp:append(dev_dir .. "/terminals.nvim")

require("snacks").setup({})
require("terminals").setup({}) -- <C-t> to toggle

require("claude").setup({
  terminals = "terminals.nvim", -- uncomment to restrict to terminals.nvim
})
