local opt = vim.opt

-- Line numbers
opt.number = true
opt.relativenumber = true
opt.cursorline = true

-- Tabs & Indentation
opt.expandtab = true
opt.shiftwidth = 2
opt.tabstop = 2
opt.smartindent = true

-- Appearance & Layout
opt.wrap = false
opt.scrolloff = 8
opt.sidescrolloff = 8
opt.signcolumn = "yes"
opt.termguicolors = true
opt.showmode = false -- Hide default mode since lualine shows it

-- Mouse support (critical for mobile / S24 Termux touch and desktop quick clicks)
opt.mouse = "a"

-- System Clipboard integration (Works seamlessly across Linux, Windows, Android Termux)
opt.clipboard = "unnamedplus"

-- Search settings
opt.ignorecase = true
opt.smartcase = true
opt.hlsearch = true
opt.incsearch = true

-- Command completion
opt.wildmenu = true
opt.wildmode = "longest:full,full"
opt.completeopt = "menu,menuone,noselect"

-- Performance & Smoothness
opt.updatetime = 250
opt.timeoutlen = 300
opt.splitright = true
opt.splitbelow = true
opt.undofile = true -- Persistent undo history
