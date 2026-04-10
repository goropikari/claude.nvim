local root = vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":h:h")
vim.opt.rtp:prepend(root)
vim.opt.rtp:append(root .. "/.dev/plenary.nvim")
