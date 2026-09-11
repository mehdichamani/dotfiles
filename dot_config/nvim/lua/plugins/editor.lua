return {
  -- Oil.nvim: Fast, elegant file navigation like a normal buffer (Perfect across PC and mobile)
  {
    "stevearc/oil.nvim",
    opts = {
      default_file_explorer = true,
      columns = { "icon" },
      view_options = {
        show_hidden = true,
      },
      float = {
        padding = 2,
        max_width = 90,
        max_height = 30,
        border = "rounded",
      },
    },
    dependencies = { "nvim-tree/nvim-web-devicons" },
    keys = {
      { "<leader>e", "<cmd>Oil --float<CR>", desc = "Open File Explorer (Float)" },
      { "-", "<cmd>Oil<CR>", desc = "Open Parent Directory" },
    },
    lazy = false,
  },

  -- Telescope: Ultra fast fuzzy finder
  {
    "nvim-telescope/telescope.nvim",
    cmd = "Telescope",
    dependencies = {
      "nvim-lua/plenary.nvim",
    },
    opts = {
      defaults = {
        prompt_prefix = "   ",
        selection_caret = "  ",
        layout_strategy = "horizontal",
        layout_config = {
          horizontal = {
            preview_width = 0.55,
          },
          width = 0.85,
          height = 0.80,
        },
        sorting_strategy = "ascending",
        borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
      },
    },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<CR>", desc = "Find Files" },
      { "<leader>fg", "<cmd>Telescope live_grep<CR>", desc = "Live Grep" },
      { "<leader>fb", "<cmd>Telescope buffers<CR>", desc = "Find Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<CR>", desc = "Help Tags" },
      { "<leader>fo", "<cmd>Telescope oldfiles<CR>", desc = "Recent Files" },
    },
  },

  -- Git signs in fringe (lightning fast & lightweight)
  {
    "lewis6991/gitsigns.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      signs = {
        add = { text = "│" },
        change = { text = "│" },
        delete = { text = "_" },
        topdelete = { text = "‾" },
        changedelete = { text = "~" },
      },
    },
    keys = {
      { "<leader>gp", "<cmd>Gitsigns preview_hunk<CR>", desc = "Preview Git Hunk" },
      { "<leader>gb", "<cmd>Gitsigns blame_line<CR>", desc = "Git Blame Line" },
    },
  },

  -- Mini.pairs: Clean auto-closing pairs without bloat
  {
    "echasnovski/mini.pairs",
    event = "VeryLazy",
    opts = {},
  },
}
