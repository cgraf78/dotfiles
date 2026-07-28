local language_policy = require("config.language-policy")
local schema_policy = require("config.schema-policy")

language_policy.add_filetypes()

local function docker_cmd()
  if vim.fn.executable("docker-language-server") == 1 then
    return { "docker-language-server", "--stdio" }
  end
  return nil
end

return {
  -- Loaded with empty sources because overlay plugins depend on null-ls modules
  -- at init time. Empty sources keeps it inert (conform + nvim-lint handle formatting).
  { "nvimtools/none-ls.nvim", opts = { sources = {} } },

  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      -- LazyVim and language extras supply many parsers already, but this
      -- local policy names the parser set our dotfiles expect everywhere.
      ensure_installed = language_policy.critical_treesitter_parsers(),
    },
  },

  {
    "saghen/blink.cmp",
    -- LazyVim's current blink integration targets the stable v1 API. Keep
    -- the plugin off its moving v2 main branch, which requires blink.lib.
    version = "1.*",
    opts = {
      keymap = {
        ["<Tab>"] = { "select_and_accept", "snippet_forward", "fallback" },
      },
    },
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        bashls = {
          before_init = function(...)
            return require("nvim_workspace.shell").before_init(...)
          end,
          root_dir = function(...)
            return require("nvim_workspace.shell").root_dir(...)
          end,
          root_markers = nil,
        },
        -- Biome's upstream root detector only attaches inside projects with a
        -- Biome config, so enabling it here improves JS/TS/CSS/JSON projects
        -- that opt in without competing with generic language servers.
        biome = {},
        cssls = {},
        superhtml = {},
        -- Override the default npm-based docker-langserver with Docker's
        -- official Go binary when shdeps/brew provides it. Otherwise leave
        -- the default command intact so Mason's fallback can provide
        -- docker-langserver.
        dockerls = {
          cmd = docker_cmd(),
        },
        jsonls = {
          settings = {
            json = {
              schemas = schema_policy.json_schemas(),
            },
          },
        },
        yamlls = {
          before_init = schema_policy.yaml_before_init,
          settings = {
            yaml = {
              schemas = schema_policy.yaml_schemas(),
            },
          },
        },
        taplo = {
          settings = {
            evenBetterToml = {
              schema = {
                associations = schema_policy.toml_schema_associations(),
              },
            },
          },
        },
      },
    },
  },
}
