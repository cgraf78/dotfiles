local M = {}

local group = vim.api.nvim_create_augroup("terminal_toggle", { clear = true })

local function is_editor_window(win)
  if not vim.api.nvim_win_is_valid(win) then
    return false
  end

  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].buftype ~= "" then return false end
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

function M.toggle()
  local current = vim.api.nvim_get_current_win()

  if is_terminal_window(current) then
    local target = editor_window()
    if target and target ~= current then
      vim.api.nvim_set_current_win(target)
    end
    return
  end

  local term = terminal_window()
  if term then
    vim.api.nvim_set_current_win(term)
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
