return {
  {
    "nvim-treesitter/nvim-treesitter",
    build = ":TSUpdate",
    event = "BufReadPost",
    config = function()
      vim.treesitter.language.add("c")
      vim.treesitter.language.add("cpp")
      vim.treesitter.language.add("python")
      vim.treesitter.language.add("lua")
      vim.treesitter.language.add("bash")
      vim.treesitter.language.add("json")
      vim.treesitter.language.add("yaml")
      vim.treesitter.language.add("javascript")
      vim.treesitter.language.add("typescript")
      vim.treesitter.language.add("markdown")
      vim.treesitter.language.add("rust")
      vim.treesitter.language.add("toml")
      vim.treesitter.language.add("cmake")
      vim.treesitter.language.add("make")
    end,
  },
}
