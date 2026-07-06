-- =====================
-- BASIC SETTINGS
-- =====================
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true

vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true

vim.opt.wrap = false
vim.opt.scrolloff = 8
vim.opt.signcolumn = "yes"

vim.opt.termguicolors = true

-- =====================
-- POWERFUL BUILT-INS (No Plugins Needed)
-- =====================
-- Enhances built-in command-line completion menu
vim.opt.wildmenu = true
vim.opt.wildmode = "longest:full,full"

-- Make the built-in file explorer (netrw) beautiful
vim.g.netrw_banner = 0       -- Hide the annoying banner header
vim.g.netrw_liststyle = 3    -- Tree style view instead of a flat list
vim.g.netrw_browse_split = 4 -- Open file in previous window
vim.g.netrw_altv = 1         -- Vertical split to the right
vim.g.netrw_winsize = 25     -- Width of the explorer window

-- Built-in Smart Auto-completion settings 
-- Use <Tab> and <S-Tab> in Insert mode to navigate completion menus
vim.opt.completeopt = "menu,menuone,noselect"

-- =====================
-- PRETTY CUSTOM COLORS
-- =====================
-- Habamax is great, let's keep it but tweak the aesthetics natively
vim.cmd("colorscheme habamax")

-- Custom adjustments to make the built-in UI elements pop cleanly
vim.api.nvim_set_hl(0, "LineNr", { fg = "#585b70" })
vim.api.nvim_set_hl(0, "CursorLineNr", { fg = "#fab387", bold = true })
vim.api.nvim_set_hl(0, "StatusLine", { bg = "#2a2b3c", fg = "#cdd6f4" })
vim.api.nvim_set_hl(0, "StatusLineNC", { bg = "#1e1e2e", fg = "#585b70" })
vim.api.nvim_set_hl(0, "VertSplit", { fg = "#313244", bg = "NONE" })

-- =====================
-- PRETTY CUSTOM STATUSLINE (Pure Lua)
-- =====================
-- Generates a lightweight, lightning-fast statusline at the bottom
function MyStatusLine()
  return table.concat({
    " %f ",                       -- Filename
    "%M",                         -- Modified flag [+]
    "%=",                         -- Right align separator
    " %y ",                       -- File type (e.g., [lua], [dockerfile])
    " %2p%% ",                    -- File percentage location
    "  %l:%c "                  -- Line:Column number
  })
end
vim.opt.statusline = "%!v:lua.MyStatusLine()"

-- =====================
-- SYNTAX & FILETYPE
-- =====================
vim.cmd("syntax on")
vim.cmd("filetype plugin indent on")

-- =====================
-- SEARCH
-- =====================
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.hlsearch = true
vim.opt.incsearch = true

-- =====================
-- KEYMAPS
-- =====================
vim.g.mapleader = " "

-- Core mappings
vim.keymap.set("n", "<leader>w", ":w<CR>", { desc = "Save File" })
vim.keymap.set("n", "<leader>q", ":q<CR>", { desc = "Quit" })
vim.keymap.set("n", "<leader>h", ":nohlsearch<CR>", { desc = "Clear Highlight" })

-- Toggle File Explorer like a sidebar (Netrw)
vim.keymap.set("n", "<leader>e", ":Lexplore<CR>", { silent = true, desc = "Toggle Explorer" })

-- Window Navigation (Move across splits effortlessly with Ctrl + Direction)
vim.keymap.set("n", "<C-h>", "<C-w>h")
vim.keymap.set("n", "<C-j>", "<C-w>j")
vim.keymap.set("n", "<C-k>", "<C-w>k")
vim.keymap.set("n", "<C-l>", "<C-w>l")

-- Text Manipulation (Move highlighted blocks of text up/down instantly)
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv")
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv")

-- Built-in Terminal Toggle (Opens an inline terminal at the bottom)
vim.keymap.set("n", "<leader>t", ":botright split | resize 15 | terminal<CR>i", { desc = "Open Terminal" })
-- Easy exit out of Terminal Mode back to Normal Mode using Esc
vim.keymap.set("t", "<Esc>", [[<C-\><C-n>]])