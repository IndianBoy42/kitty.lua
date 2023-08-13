-- Get the second window in the same tab as the neovim instance
local K = {}
local kutils = require "kitty.utils"
local defaults = {
  title = "Kitty.nvim",
  attach_to_existing_os_win = true,
  attach_to_existing_kt_win = true,
  attach_to_existing_tab = true,
}

function K.attach_to(cfg, ls)
  local found = ls:focused_window()
  -- Get previous active window in focused tab
  if not cfg.attach_to_current_win and cfg.attach_to_existing_kt_win then
    for _, winid in ipairs(found.tab.active_window_history) do
      if winid ~= found.win.id and ls:window_by_id(winid) then cfg.attach_to_current_win = winid end
    end
  end
  -- Find another existing tab in the current OS window
  if not cfg.attach_to_current_win and cfg.attach_to_existing_tab then
    for _, tab in ipairs(found.os_win.tabs) do
      if not tab.is_focused then cfg.attach_to_current_win = tab.active_window_history[1] end
    end
  end
  -- Find another existing OS window
  if not cfg.attach_to_current_win and cfg.attach_to_existing_os_win then
    for _, os_win in ipairs(ls.data) do
      if not os_win.is_focused then
        for _, tab in ipairs(os_win.tabs) do
          if tab.is_active then cfg.attach_to_current_win = tab.active_window_history[1] end
        end
      end
    end
  end
end

K.setup = function(cfg, cb)
  -- TODO: other_tab
  cfg = vim.tbl_extend("keep", cfg or {}, defaults)

  local CW = require "kitty.current_win"
  if CW.title == nil then
    if cfg.current_win_setup then
      CW.setup(cfg.current_win_setup)
    else
      error "kitty.current_win not setup() yet"
      return
    end
  end

  -- TODO: Defer calls to after attaching
  -- setmetatable(K, {
  --   __index = function(m, k)
  --     return nil
  --   end,
  -- })

  CW.ls(vim.schedule_wrap(function(data)
    local ls = require("kitty.ls").from_json(data)
    _G.kitty_initial_ls = ls
    -- FIXME: this seems unreliable, sometimes we are still in the kitty window
    local found = ls:focused_os_win()

    if not found then
      -- TODO: is this the best idea? probably
      cfg.attach_to_current_win = kutils.current_win_id()
    end

    K.attach_to(cfg, ls)

    -- Couldn't find any existing window
    if not cfg.attach_to_current_win then
      vim.notify "Creating a new Kitty window"
      if cfg.create_new_win ~= false then K.instance = CW.launch(cfg, cfg.create_new_win or true) end
    else
      vim.notify("Found Kitty window " .. tostring(cfg.attach_to_current_win))
      -- TODO: send the nvim injections
      local win = ls:window_by_id(cfg.attach_to_current_win)
      cfg = vim.tbl_deep_extend("keep", cfg, require("kitty.ls").term_config(win))
      K.instance = require("kitty.term"):new(cfg)
    end

    if K.instance then K.setup = function(_) return K end end

    setmetatable(K, {
      __index = function(m, k)
        local ret = K.instance[k]
        if type(ret) == "function" then
          local f = function(...) return ret(K.instance, ...) end
          m[k] = f
          return f
        else
          return ret
        end
      end,
    })

    -- K.set_window_title(K.title)

    if cb then cb(K, ls) end
  end))
end

K.attach_all = function(ls, cfg)
  local Term = require "kitty.term"
  local terms = {}
  cfg = cfg or {}
  for id, t in pairs(ls:all_windows()) do
    terms[id] = Term:new(vim.tbl_deep_extend("keep", {
      attach_to_current_win = id,
    }, type(cfg) == "table" and cfg or cfg(t)))
  end
  return terms
end

return K
