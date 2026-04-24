local M = {}

local session_files = {}
local session_set = {}
local cache = nil
local cache_set = nil
local dirty = true

vim.api.nvim_create_autocmd("BufEnter", {
  callback = function(args)
    if not vim.api.nvim_buf_is_valid(args.buf) or vim.bo[args.buf].buftype ~= "" then
      return
    end
    local name = vim.api.nvim_buf_get_name(args.buf)
    if name == "" then
      return
    end
    if session_set[name] then
      for i, f in ipairs(session_files) do
        if f == name then
          table.remove(session_files, i)
          break
        end
      end
    end
    table.insert(session_files, 1, name)
    session_set[name] = true
    dirty = true
  end,
})

function M.get()
  if not dirty and cache then
    return cache, cache_set
  end

  local results = {}
  local seen = {}
  local n = 0

  for _, f in ipairs(session_files) do
    if not seen[f] then
      seen[f] = true
      n = n + 1
      results[n] = f
    end
  end

  for _, f in ipairs(vim.v.oldfiles) do
    if n >= 100 then
      break
    end
    if not seen[f] and vim.uv.fs_stat(f) then
      seen[f] = true
      n = n + 1
      results[n] = f
    end
  end

  cache = results
  cache_set = seen
  dirty = false
  return results, seen
end

return M
