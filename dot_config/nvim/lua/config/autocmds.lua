local autocmd = vim.api.nvim_create_autocmd
local augroup = vim.api.nvim_create_augroup

local general_group = augroup("GeneralSettings", { clear = true })

-- Highlight on yank (sleek visual feedback when copying)
autocmd("TextYankPost", {
  group = general_group,
  pattern = "*",
  callback = function()
    vim.highlight.on_yank({ higroup = "IncSearch", timeout = 150 })
  end,
  desc = "Briefly highlight yanked text",
})

-- Close certain utility windows effortlessly with just 'q'
autocmd("FileType", {
  group = general_group,
  pattern = {
    "help",
    "man",
    "qf",
    "lspinfo",
    "checkhealth",
    "notify",
  },
  callback = function(event)
    vim.bo[event.buf].buflisted = false
    vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = event.buf, silent = true })
  end,
  desc = "Close utility buffers with q",
})

-- Return to last edit position when opening files
autocmd("BufReadPost", {
  group = general_group,
  callback = function()
    local mark = vim.api.nvim_buf_get_mark(0, '"')
    local lcount = vim.api.nvim_buf_line_count(0)
    if mark[1] > 0 and mark[1] <= lcount then
      pcall(vim.api.nvim_win_set_cursor, 0, mark)
    end
  end,
  desc = "Go to last cursor location",
})

-- When in diff mode (e.g. cdiff), make pressing 'q' quit all splits immediately
autocmd("OptionSet", {
  group = general_group,
  pattern = "diff",
  callback = function()
    if vim.wo.diff then
      vim.keymap.set("n", "q", "<cmd>qa<cr>", { buffer = 0, silent = true, desc = "Quit diff view" })
    end
  end,
  desc = "Map q to quit all when entering diff mode",
})

