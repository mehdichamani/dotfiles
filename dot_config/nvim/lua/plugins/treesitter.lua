return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = { "BufReadPost", "BufNewFile" },
    cmd = { "TSUpdateSync", "TSUpdate", "TSInstall" },
    opts = {
      highlight = {
        enable = true,
        additional_vim_regex_highlighting = false,
      },
      indent = { enable = true },
      ensure_installed = {
        "bash",
        "fish",
        "lua",
        "markdown",
        "markdown_inline",
        "json",
        "yaml",
        "toml",
        "vim",
        "vimdoc",
      },
    },
    config = function(_, opts)
      -- On systems without a C compiler (e.g. minimal Termux install), fail gracefully without crashing
      local ok, ts = pcall(require, "nvim-treesitter.configs")
      if ok then
        ts.setup(opts)
      end
    end,
  },
}
