-- Leader key must be set before lazy.nvim
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Load core configurations
require("config.options")
require("config.keymaps")
require("config.autocmds")

-- Bootstrap & load lazy.nvim plugins
require("config.lazy")