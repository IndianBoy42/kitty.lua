-- Helpers for querying/using the output of kitty @ ls
local M = {}
local meta_M = {}
M = setmetatable(M, meta_M)
M.json_to_buffer = vim.schedule_wrap(function(_, raw)
  vim.cmd.tabnew()
  vim.api.nvim_buf_set_lines(0, 0, 0, false, vim.split(raw, "\n"))
  vim.opt.filetype = "json"
end)

local methods = {}
function methods:focused_window()
  for _, os_win in ipairs(self.data) do
    if os_win.is_focused then
      for _, tab in ipairs(os_win.tabs) do
        if tab.is_focused then
          for _, win in ipairs(tab.windows) do
            if win.is_focused then return win, tab, os_win end
          end
        end
      end
    end
  end
end
function methods:focused_tab()
  for _, os_win in ipairs(self.data) do
    if os_win.is_focused then
      for _, tab in ipairs(os_win.tabs) do
        if tab.is_focused then return tab, os_win end
      end
    end
  end
end
function methods:window_by_id(id)
  return self:all_windows()[id]
  -- for _, os_win in ipairs(self.data) do
  --   for _, tab in ipairs(os_win.tabs) do
  --     for _, win in ipairs(tab.windows) do
  --       if win.id == id then
  --         return win, tab, os_win
  --       end
  --     end
  --   end
  -- end
end
function methods:tabs()
  for _, os_win in ipairs(self.data) do
    if os_win.is_focused then return os_win.tabs end
  end
end
function methods:all_windows(tbl)
  if tbl == nil and self._all_windows_cache then return self._all_windows_cache end
  tbl = tbl or {}
  for _, tab in pairs(self:all_tabs()) do
    for _, win in ipairs(tab.windows) do
      tbl[win.id] = win
    end
  end
  rawset(self, "_all_windows_cache", tbl)
  return tbl
end
function methods:all_tabs(tbl)
  if tbl == nil and self._all_tabs_cache then return self._all_tabs_cache end
  tbl = tbl or {}
  for _, os_win in ipairs(self.data) do
    for _, tab in ipairs(os_win.tabs) do
      tbl[tab.id] = tab
    end
  end
  rawset(self, "_all_tabs_cache", tbl)
  return tbl
end

local metatbl = {
  __index = methods,
  __newindex = function() end,
}
M.from_json = function(data) return setmetatable({ data = data }, metatbl) end
M.term_config = function(ls_win)
  -- TODO: adapt the ls information into require'kitty.term'.setup options
  return {
    title = ls_win.title,
  }
end
return M
