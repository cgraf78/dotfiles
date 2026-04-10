local M = {}

local function is_normal_buffer(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end

  if not vim.bo[bufnr].buflisted or vim.bo[bufnr].buftype ~= "" then
    return false
  end

  return vim.bo[bufnr].filetype ~= "NvimTree"
end

local function replacement_buffer(target)
  local alternate = vim.fn.bufnr("#")
  if alternate > 0 and alternate ~= target and is_normal_buffer(alternate) then
    return alternate
  end

  for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    if info.bufnr ~= target and is_normal_buffer(info.bufnr) then
      return info.bufnr
    end
  end
end

function M.pick(target)
  return replacement_buffer(target)
end

function M.delete(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.bo[bufnr].filetype == "NvimTree" then
    vim.cmd("silent! NvimTreeClose")
    return
  end

  local force = vim.bo[bufnr].buftype == "terminal"

  local replacement = M.pick(bufnr)

  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      if replacement then
        vim.api.nvim_win_set_buf(win, replacement)
      else
        vim.api.nvim_win_call(win, function()
          vim.cmd("enew")
        end)
      end
    end
  end

  vim.api.nvim_buf_delete(bufnr, { force = force })
end

return M
