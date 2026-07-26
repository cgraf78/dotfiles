-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

require("config.keymaps.vscode")

local map = vim.keymap.set

-- Exit insert/terminal mode
map("i", "kj", "<Esc>", { desc = "Exit insert mode" })
map("t", "kj", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Yank history. tmux forwards Ctrl-Shift-v as Esc[778899~ so it does not
-- fall through to tmux's plain Ctrl-v paste binding.
local function open_yank_history()
  -- LazyVim.pick.picker can be nil (no picker resolved yet / minimal session);
  -- guard so <C-S-v> falls through to the YankyRingHistory command instead of
  -- erroring on a nil index.
  local picker = LazyVim.pick.picker and LazyVim.pick.picker.name
  if picker == "telescope" then
    require("telescope").extensions.yank_history.yank_history({})
  elseif picker == "snacks" then
    Snacks.picker.yanky() ---@diagnostic disable-line: undefined-field
  else
    vim.cmd([[YankyRingHistory]])
  end
end
map({ "n", "x", "i" }, "<C-S-v>", open_yank_history, { desc = "Open Yank History" })
map(
  { "n", "x", "i" },
  vim.keycode("<Esc>") .. "[778899~",
  open_yank_history,
  { desc = "Open Yank History" }
)

local function listed_buffer_count()
  local count = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.bo[bufnr].buflisted then
      count = count + 1
    end
  end
  return count
end

local function tmux_window_count()
  if not vim.env.TMUX then
    return 0
  end
  local output = vim.fn.system({ "tmux", "display-message", "-p", "#{session_windows}" })
  if vim.v.shell_error ~= 0 then
    return 0
  end
  return tonumber((output or ""):match("%d+")) or 0
end

local function tmux_window_position()
  if not vim.env.TMUX then
    return 0, 0, 0
  end

  local output = vim.fn.system({
    "tmux",
    "display-message",
    "-p",
    "#{window_index} #{session_windows} #{base-index}",
  })
  if vim.v.shell_error ~= 0 then
    return 0, 0, 0
  end

  local index, count, base = (output or ""):match("(%d+)%s+(%d+)%s+(%d+)")
  return tonumber(index) or 0, tonumber(count) or 0, tonumber(base) or 0
end

local function tmux_client_is_nested()
  if not vim.env.TMUX then
    return false
  end

  local output = vim.fn.system({ "tmux", "display-message", "-p", "#{client_termname}" })
  if vim.v.shell_error ~= 0 then
    return false
  end

  local term = vim.trim(output or "")
  return term:match("^tmux") ~= nil or term:match("^screen") ~= nil
end

local function outer_terminal_is_vscode()
  if not vim.env.TMUX then
    return false
  end

  local output = vim.fn.system({
    "tmux",
    "list-clients",
    "-F",
    "#{client_activity} #{client_termtype}",
  })
  if vim.v.shell_error ~= 0 then
    return false
  end

  local best_activity, best_termtype = nil, nil
  for line in vim.gsplit(output, "\n", { trimempty = true }) do
    local activity, termtype = line:match("^(%d+)%s+(.*)$")
    if activity then
      activity = tonumber(activity)
      if not best_activity or activity > best_activity then
        best_activity = activity
        best_termtype = termtype
      end
    end
  end

  return best_termtype ~= nil and best_termtype:match("^xterm%.js") ~= nil
end

local function request_vscode_tab_switch(direction)
  vim.fn.jobstart({ "vscode-switch-tab", direction }, { detach = true })
end

local function request_wezterm_tab_switch(name, direction)
  local ok, vars = pcall(require, "config.wezterm-vars")
  if not ok or type(vars.set) ~= "function" then
    return
  end
  local nonce = tostring((vim.uv or vim.loop).hrtime())
  vars.set(name, direction .. ":" .. nonce)
end

local function request_wezterm_tab_move(name, direction)
  local ok, vars = pcall(require, "config.wezterm-vars")
  if not ok or type(vars.set) ~= "function" then
    return
  end
  local nonce = tostring((vim.uv or vim.loop).hrtime())
  vars.set(name, direction .. ":" .. nonce)
end

local function smart_tab_switch(direction)
  if listed_buffer_count() > 1 then
    vim.cmd(direction == "previous" and "BufferLineCyclePrev" or "BufferLineCycleNext")
    return
  end

  if tmux_window_count() > 1 then
    vim.fn.system({ "tmux", direction == "previous" and "previous-window" or "next-window" })
    return
  end

  if outer_terminal_is_vscode() then
    request_vscode_tab_switch(direction)
    return
  end

  local var_name = tmux_client_is_nested() and "DOT_PARENT_SWITCH_TAB" or "DOT_SWITCH_TAB"
  request_wezterm_tab_switch(var_name, direction)
end

local function smart_tab_move(direction)
  if listed_buffer_count() > 1 then
    vim.cmd(direction == "left" and "BufferLineMovePrev" or "BufferLineMoveNext")
    return
  end

  local index, count, base = tmux_window_position()
  if count > 1 then
    local last = base + count - 1
    if direction == "left" and index > base then
      vim.fn.system({ "tmux", "swap-window", "-d", "-t", ":-" })
    elseif direction == "right" and index < last then
      vim.fn.system({ "tmux", "swap-window", "-d", "-t", ":+" })
    end
    return
  end

  -- Moves stop here for VS Code clients: VS Code exposes no command to
  -- reorder integrated-terminal tabs (drag-only), so there is nothing sane
  -- to bubble the move to. The guard still matters -- falling through would
  -- write a WezTerm-only OSC escape at VS Code's terminal for nothing.
  if outer_terminal_is_vscode() then
    return
  end

  local var_name = tmux_client_is_nested() and "DOT_PARENT_MOVE_TAB" or "DOT_MOVE_TAB"
  request_wezterm_tab_move(var_name, direction)
end

-- Buffer cycling (forwarded from wezterm when nvim is focused). If nvim has
-- only one listed buffer, bubble to tmux; if tmux also has one window, bubble
-- to WezTerm.
map("n", "<C-Tab>", function()
  smart_tab_switch("next")
end, { desc = "Next buffer/tab" })
map("n", "<C-S-Tab>", function()
  smart_tab_switch("previous")
end, { desc = "Previous buffer/tab" })
map("n", "<M-{>", function()
  smart_tab_move("left")
end, { desc = "Move buffer/tab left" })
map("n", "<M-}>", function()
  smart_tab_move("right")
end, { desc = "Move buffer/tab right" })

-- Join lines without cursor jump
map("n", "J", "mzJ`z", { desc = "Join lines (keep cursor)" })

-- Override LazyVim's C-hjkl with tmux-navigator so pane navigation
-- works seamlessly between vim splits and tmux panes.
map("n", "<C-h>", "<cmd>TmuxNavigateLeft<cr>", { desc = "Navigate left" })
map("n", "<C-j>", "<cmd>TmuxNavigateDown<cr>", { desc = "Navigate down" })
map("n", "<C-k>", "<cmd>TmuxNavigateUp<cr>", { desc = "Navigate up" })
map("n", "<C-l>", "<cmd>TmuxNavigateRight<cr>", { desc = "Navigate right" })
