return {
  {
    "LazyVim/LazyVim",
    init = function()
      -- This file is only the explicit human command surface. Automatic
      -- one-file editor formatting/linting is wired through sley hook commands
      -- in formatting.lua and linting.lua, where latency and diagnostics are
      -- handled by the normal Neovim formatter/linter integrations.
      local function current_repo_root()
        local ok, workspace = pcall(require, "nvim_workspace")
        if not ok then
          return nil
        end

        -- Explicit sley commands operate on the active file's repo. For
        -- scratch/special buffers, abort instead of inheriting nvim's cwd.
        local root_ok, root = pcall(workspace.current_file_repo_root)
        if root_ok and type(root) == "string" and root ~= "" then
          return root
        end
        return nil
      end

      local function run(subcommand)
        return function()
          local cwd = current_repo_root()
          if not cwd then
            vim.notify("Sley command needs a valid buffer repo root", vim.log.levels.WARN)
            return
          end

          -- These commands are explicit user actions. They open a terminal
          -- instead of running on save or commit so editor integration cannot
          -- accidentally inherit broad repo-workflow latency.
          vim.cmd("botright split")
          vim.fn.jobstart({ "sley", subcommand }, {
            cwd = cwd,
            term = true,
          })
          vim.cmd("startinsert")
        end
      end

      vim.api.nvim_create_user_command("SleyStatus", run("status"), {
        desc = "Show current repo status via sley",
      })
      vim.api.nvim_create_user_command("SleyCheck", run("check"), {
        desc = "Run the read-only sley check phase",
      })
      vim.api.nvim_create_user_command("SleyReady", run("ready"), {
        desc = "Run the aggregate sley readiness report",
      })
    end,
  },
}
