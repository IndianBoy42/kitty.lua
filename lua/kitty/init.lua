-- Get the second window in the same tab as the neovim instance
local K = {}
local defaults = {
  title = "Kitty.nvim",
  attach_to_existing_os_win = true,
  attach_to_existing_kt_win = true,
  attach_to_existing_tab = true,
}
K.setup = function(cfg, cb)
  -- TODO: other_tab
  cfg = vim.tbl_extend("keep", cfg or {}, defaults)

  local CW = require("kitty.current_win").setup()
  if CW.title == nil then
    error "kitty.current_win not setup() yet"
    return
  end

  K.setup = function(_)
    return K
  end

  CW.ls(vim.schedule_wrap(function(data)
    local KT

    local ls = require("kitty.ls").from_json(data)
    local found_tab, found_os_win = ls:focused_tab()

    -- Get previous active window in focused tab
    if not cfg.attach_to_current_win and cfg.attach_to_existing_kt_win then
      if not found_tab then
        error "Couldn't find the current window, this is a bug in kitty.current_win"
      end
      for i, winid in ipairs(found_tab.active_window_history) do
        if i > 1 and ls:window_by_id(winid) then
          cfg.attach_to_current_win = winid
        end
      end
    end
    -- Find another existing tab in the current OS window
    if not cfg.attach_to_current_win and cfg.attach_to_existing_tab then
      for _, tab in ipairs(found_os_win.tabs) do
        if not tab.is_focused then
          cfg.attach_to_current_win = tab.active_window_history[1]
        end
      end
    end
    -- Find another existing OS window
    if not cfg.attach_to_current_win and cfg.attach_to_existing_os_win then
      for _, os_win in ipairs(ls.data) do
        if not os_win.is_focused then
          for _, tab in ipairs(os_win.tabs) do
            if tab.is_active then
              cfg.attach_to_current_win = tab.active_window_history[1]
            end
          end
        end
      end
    end
    -- Couldn't find any existing window
    if not cfg.attach_to_current_win then
      vim.notify "Creating other win"
      KT = CW.launch(cfg, cfg.create_new_win or "window")
    else
      vim.notify("Found other win " .. cfg.attach_to_current_win)
      KT = require("kitty.term"):new(cfg)
    end

    setmetatable(K, {
      __index = function(m, k)
        local ret = KT[k]
        if type(ret) == "function" then
          local f = function(...)
            return ret(KT, ...)
          end
          m[k] = f
          return f
        else
          return ret
        end
      end,
    })

    -- K.set_window_title(K.title)

    if cb then
      cb(K)
    end
  end))
end
return K
