local keymap = vim.keymap.set
local opts = { noremap = true, silent = true }

-- General convenience
keymap("n", "<leader>w", ":w<CR>", { desc = "Save File", silent = true })
keymap("n", "<leader>q", ":q<CR>", { desc = "Quit Window", silent = true })
keymap("n", "q", ":q<CR>", { desc = "Quick Quit", silent = true })
keymap("n", "Q", ":qa<CR>", { desc = "Quit All Splits (Diff / Multi-window)", silent = true })
keymap("n", "<leader>Q", ":qa!<CR>", { desc = "Quit All Force", silent = true })
keymap("n", "<leader>h", ":nohlsearch<CR>", { desc = "Clear Highlight", silent = true })

-- Buffer Navigation (Super easy tab switching)
keymap("n", "<Tab>", ":bnext<CR>", { desc = "Next Buffer", silent = true })
keymap("n", "<S-Tab>", ":bprevious<CR>", { desc = "Previous Buffer", silent = true })
keymap("n", "<leader>bd", ":bdelete<CR>", { desc = "Close Buffer", silent = true })

-- Window Navigation (Move across splits effortlessly with Ctrl + Direction)
keymap("n", "<C-h>", "<C-w>h", { desc = "Move to Left Window" })
keymap("n", "<C-j>", "<C-w>j", { desc = "Move to Lower Window" })
keymap("n", "<C-k>", "<C-w>k", { desc = "Move to Upper Window" })
keymap("n", "<C-l>", "<C-w>l", { desc = "Move to Right Window" })

-- Window Resize
keymap("n", "<C-Up>", ":resize +2<CR>", opts)
keymap("n", "<C-Down>", ":resize -2<CR>", opts)
keymap("n", "<C-Left>", ":vertical resize -2<CR>", opts)
keymap("n", "<C-Right>", ":vertical resize +2<CR>", opts)

-- Text Manipulation (Move highlighted blocks of text up/down)
keymap("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move Line Down", silent = true })
keymap("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move Line Up", silent = true })

-- Stay in indent mode after shifting
keymap("v", "<", "<gv", opts)
keymap("v", ">", ">gv", opts)

-- Terminal navigation & toggle
keymap("n", "<leader>t", ":botright split | resize 12 | terminal<CR>i", { desc = "Open Terminal", silent = true })
keymap("t", "<Esc>", [[<C-\><C-n>]], { desc = "Exit Terminal Mode" })
