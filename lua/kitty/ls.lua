-- Helpers for querying/using the output of kitty @ ls
local M = {}
local meta_M = {}
local kutils = require "kitty.utils"
M = setmetatable(M, meta_M)
M.json_to_buffer = vim.schedule_wrap(function(_, raw)
  kutils.dump_to_buffer("tab", raw, function() vim.opt.filetype = "json" end)
end)

local function with_cache(tbl, key, fn)
  if tbl[key] then return tbl[key] end
  local res = fn(tbl, key)
  rawset(tbl, key, res)
  return res
end
local function all_windows(self)
  local tbl = {}
  for _, tab in pairs(self:all_tabs()) do
    for _, win in ipairs(tab.windows) do
      tbl[win.id] = win
    end
  end
  return tbl
end
local function all_tabs(self)
  local tbl = {}
  for _, os_win in ipairs(self.data) do
    for _, tab in ipairs(os_win.tabs) do
      tbl[tab.id] = tab
    end
  end
  return tbl
end
local function focused_window(self)
  local focused = self:focused_tab()
  if not focused then return nil end
  local os_win = focused.os_win
  local tab = focused.tab
  for _, win in ipairs(tab.windows) do
    if win.is_focused then return { win = win, tab = tab, os_win = os_win } end
  end
end
local function focused_tab(self)
  local os_win = self:focused_os_win()
  if not os_win then return nil end
  for _, tab in ipairs(os_win.tabs) do
    if tab.is_focused then return { tab = tab, os_win = os_win } end
  end
end
local function focused_os_win(self)
  for _, os_win in ipairs(self.data) do
    if os_win.is_focused then return os_win end
  end
end

local methods = {}
function methods:focused_window() return with_cache(self, "__focused_window", focused_window) end
function methods:focused_tab() return with_cache(self, "__focused_tab", focused_tab) end
function methods:focused_os_win() return with_cache(self, "__focused_os_win", focused_os_win) end
function methods:window_by_id(id)
  if type(id) == "string" then id = tonumber(id) end
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
function methods:all_windows() return with_cache(self, "__all_windows", all_windows) end
function methods:all_tabs() return with_cache(self, "__all_tabs", all_tabs) end

local metatbl = {
  __index = methods,
  __newindex = function() end,
}
M.from_json = function(data) return setmetatable({ data = data }, metatbl) end
M.term_config = function(win)
  -- TODO: adapt the ls information into require'kitty.term'.setup options
  return {
    title = win.title,
  }
end
M.shell = function(win)
  local o = {}
  for _, p in ipairs(win.foreground_processes) do
    if vim.endswith(p.cmdline[1], "sh") then
      o.cmdline = p.cmdline
      o.sh = vim.fs.basename(p.cmdline[1])
    end
  end
  return o
end

return M
