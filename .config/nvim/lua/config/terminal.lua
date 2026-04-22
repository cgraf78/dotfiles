local M = {}

local group = vim.api.nvim_create_augroup("terminal_toggle", { clear = true })

local function is_editor_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then
    return false
  end
  return vim.bo[buf].filetype ~= "NvimTree"
end

local function is_terminal_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  return vim.bo[buf].buftype == "terminal"
end

local function editor_window()
  local win = vim.t.last_editor_win
  if win and vim.api.nvim_win_is_valid(win) and is_editor_window(win) then
    return win
  end

  for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_editor_window(candidate) then
      return candidate
    end
  end
end

local function terminal_window()
  local win = vim.t.last_terminal_win
  if win and vim.api.nvim_win_is_valid(win) and is_terminal_window(win) then
    return win
  end

  for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if is_terminal_window(candidate) then
      return candidate
    end
  end
end

function M.open_bottom()
  vim.cmd("botright 12split")
  vim.cmd("terminal")
  vim.t.last_terminal_win = vim.api.nvim_get_current_win()
  vim.cmd("startinsert")
end

function M.open_top()
  vim.cmd("topleft 12split")
  vim.cmd("terminal")
  vim.t.last_terminal_win = vim.api.nvim_get_current_win()
  vim.cmd("startinsert")
end

function M.open_right()
  vim.cmd("botright vsplit")
  vim.cmd("vertical resize 50")
  vim.cmd("terminal")
  vim.t.last_terminal_win = vim.api.nvim_get_current_win()
  vim.cmd("startinsert")
end

function M.open_left()
  vim.cmd("topleft vsplit")
  vim.cmd("vertical resize 50")
  vim.cmd("terminal")
  vim.t.last_terminal_win = vim.api.nvim_get_current_win()
  vim.cmd("startinsert")
end

local function find_terminal_buf()
  local saved = vim.t.last_terminal_buf
  if saved and vim.api.nvim_buf_is_valid(saved) and vim.bo[saved].buftype == "terminal" then
    return saved
  end
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == "terminal" then
      return buf
    end
  end
end

function M.toggle()
  local current = vim.api.nvim_get_current_win()

  -- From terminal: hide the window, go back to editor.
  if is_terminal_window(current) then
    vim.t.last_terminal_buf = vim.api.nvim_win_get_buf(current)
    -- Suppress auto-exit: closing the terminal window may leave only
    -- aux windows visible (e.g. ephemeral views + NvimTree), but the user is
    -- just toggling, not quitting.
    vim.g.aux_exit_suppressed = true
    vim.api.nvim_win_close(current, false)
    local target = editor_window()
    if target then
      vim.api.nvim_set_current_win(target)
    end
    vim.schedule(function()
      vim.g.aux_exit_suppressed = false
    end)
    return
  end

  -- If a terminal window is already visible, just focus it.
  local term = terminal_window()
  if term then
    vim.api.nvim_set_current_win(term)
    vim.cmd("startinsert")
    return
  end

  -- Re-show a hidden terminal buffer if one exists.
  local term_buf = find_terminal_buf()
  if term_buf then
    vim.cmd("botright 12split")
    vim.api.nvim_win_set_buf(0, term_buf)
    vim.t.last_terminal_win = vim.api.nvim_get_current_win()
    vim.cmd("startinsert")
    return
  end

  M.open_bottom()
end

vim.api.nvim_create_autocmd("WinEnter", {
  group = group,
  callback = function()
    local win = vim.api.nvim_get_current_win()
    if is_terminal_window(win) then
      vim.t.last_terminal_win = win
    elseif is_editor_window(win) then
      vim.t.last_editor_win = win
    end
  end,
})

return M
