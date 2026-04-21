local wanted_parsers = {
  "bash",
  "c",
  "cmake",
  "cpp",
  "css",
  "diff",
  "dockerfile",
  "doxygen",
  "git_config",
  "git_rebase",
  "gitcommit",
  "go",
  "html",
  "ini",
  "jinja",
  "javascript",
  "json",
  "lua",
  "make",
  "markdown",
  "markdown_inline",
  "python",
  "regex",
  "rust",
  "starlark",
  "thrift",
  "toml",
  "typescript",
  "vimdoc",
  "yaml",
}

return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = function()
      require("nvim-treesitter").install(wanted_parsers)
    end,
    event = "BufReadPost",
    dependencies = {
      "nvim-treesitter/nvim-treesitter-textobjects",
    },
    config = function()
      -- Install missing parsers on first load.
      local installed = require("nvim-treesitter").get_installed()
      local installed_set = {}
      for _, lang in ipairs(installed) do
        installed_set[lang] = true
      end
      local missing = {}
      for _, lang in ipairs(wanted_parsers) do
        if not installed_set[lang] then
          missing[#missing + 1] = lang
        end
      end
      if #missing > 0 then
        require("nvim-treesitter").install(missing)
      end

      -- Nvim 0.12: highlight and indent are built-in; enable via autocmd.
      vim.api.nvim_create_autocmd("FileType", {
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })

      -- Textobjects — keymaps registered via nvim-treesitter-textobjects.
      require("nvim-treesitter-textobjects").setup({
        select = { lookahead = true },
        move = { set_jumps = true },
      })

      local map = vim.keymap.set
      map({ "x", "o" }, "af", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@function.outer",
          "textobjects"
        )
      end)
      map({ "x", "o" }, "if", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@function.inner",
          "textobjects"
        )
      end)
      map({ "x", "o" }, "ac", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@class.outer",
          "textobjects"
        )
      end)
      map({ "x", "o" }, "ic", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@class.inner",
          "textobjects"
        )
      end)
      map({ "x", "o" }, "ab", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@block.outer",
          "textobjects"
        )
      end)
      map({ "x", "o" }, "ib", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@block.inner",
          "textobjects"
        )
      end)
      map({ "x", "o" }, "ap", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@parameter.outer",
          "textobjects"
        )
      end)
      map({ "x", "o" }, "ip", function()
        require("nvim-treesitter-textobjects.select").select_textobject(
          "@parameter.inner",
          "textobjects"
        )
      end)

      map("n", "]m", function()
        require("nvim-treesitter-textobjects.move").goto_next_start(
          "@function.outer",
          "textobjects"
        )
      end)
      map("n", "]]", function()
        require("nvim-treesitter-textobjects.move").goto_next_start("@class.outer", "textobjects")
      end)
      map("n", "[m", function()
        require("nvim-treesitter-textobjects.move").goto_previous_start(
          "@function.outer",
          "textobjects"
        )
      end)
      map("n", "[[", function()
        require("nvim-treesitter-textobjects.move").goto_previous_start(
          "@class.outer",
          "textobjects"
        )
      end)
    end,
  },
}
