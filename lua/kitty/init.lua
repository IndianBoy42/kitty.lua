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
  local function inner()
    local focused = ls:focused_window()

    local pid = vim.fn.getpid()
    local cwd = vim.fs.normalize(vim.loop.cwd())
    local nvim_running_in_kitty = false
    for _, p in ipairs(focused.win.foreground_processes) do
      if p.cmdline[1] == "nvim" or p.pid == pid then nvim_running_in_kitty = true end
    end
    if not nvim_running_in_kitty then
      cfg.attach_to_win = focused.win.id
      return
    end

    local candidates = {}
    local function filter_by_fg(winid, win)
      table.insert(candidates, win)
      for _, p in ipairs(win.foreground_processes) do
        if p.cmdline[1] and p.cmdline[1]:sub(-2) == "sh" and vim.fs.normalize(p.cwd) == cwd then return true end
      end
      return false
    end

    -- TODO: can simplify: sort all windows and then search through in one loop
    -- Get previous active window in focused tab
    if not cfg.attach_to_win and cfg.attach_to_existing_kt_win then
      for _, winid in ipairs(focused.tab.active_window_history) do
        local win = ls:window_by_id(winid)
        if winid ~= focused.win.id and win and filter_by_fg(winid, win) then cfg.attach_to_win = winid end
      end
    end
    -- Find another existing tab in the current OS window
    if not cfg.attach_to_win and cfg.attach_to_existing_tab then
      for _, tab in ipairs(focused.os_win.tabs) do
        if not tab.is_focused then
          for _, winid in ipairs(tab.active_window_history) do
            local win = ls:window_by_id(winid)
            if win and filter_by_fg(winid, win) then cfg.attach_to_win = winid end
          end
        end
      end
    end
    -- Find another existing OS window
    if not cfg.attach_to_win and cfg.attach_to_existing_os_win then
      for _, os_win in ipairs(ls.data) do
        if not os_win.is_focused then
          for _, tab in ipairs(os_win.tabs) do
            -- if tab.is_active then
            for _, winid in ipairs(tab.active_window_history) do
              local win = ls:window_by_id(winid)
              if win and filter_by_fg(winid, win) then cfg.attach_to_win = winid end
            end
            -- end
          end
        end
      end
    end

    if not cfg.attach_to_win and cfg.redirect_existing_shell then
      local is_nvim_attached = require("kitty.ls").is_nvim_attached
      -- Recheck filtered out candidates for shells
      for _, win in ipairs(candidates) do
        for _, p in ipairs(win.foreground_processes) do
          -- TODO: I should somehow check if an existing nvim is attached to this shell
          -- Maybe use set-user-var
          if p.cmdline[1] and p.cmdline[1]:sub(-2) == "sh" and is_nvim_attached(win) then
            cfg.attach_to_win = win.id
            cfg.cd_to_cwd = cwd
          end
        end
      end
    end
  end

  if not pcall(inner) then vim.defer_fn(function() inner() end, 200) end
end

local function inject_env(sh, k, env, value)
  if sh == "fish" then
    k:send("set -x " .. k .. " " .. value .. "\r")
  else
    k:send("export " .. k .. "=" .. value .. "\r")
    -- vim.notify("Use a better shell or give me a PR (unimplemented inject env in " .. sh .. " shell)")
  end
end

K.setup = function(cfg, cb)
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
    local focused = ls:focused_os_win()

    if not focused then
      -- TODO: is this the best idea? probably not
      cfg.attach_to_win = kutils.current_win_id()
    end

    K.attach_to(cfg, ls)

    -- Couldn't find any existing window
    if not cfg.attach_to_win then
      -- vim.notify("Creating a new Kitty window", vim.log.levels.INFO)
      if cfg.create_new_win ~= false then
        -- K.instance = CW.launch(cfg, cfg.create_new_win or true)
        K.instance = CW.sub_window(cfg, cfg.create_new_win or true)
      end
    else
      -- vim.notify("Found Kitty window " .. tostring(cfg.attach_to_win), vim.log.levels.INFO)
      local win = ls:window_by_id(cfg.attach_to_win)
      local L = require "kitty.ls"
      cfg = vim.tbl_deep_extend("keep", cfg, L.term_config(win))
      K.instance = require("kitty.term"):new(cfg)
      if cfg.cd_to_cwd then
        K.instance:defer_till_open { "cmd", { "cd " .. cfg.cd_to_cwd } }
        -- K.instance:cmd("cd " .. cfg.cd_to_cwd)
      end
    end

    if K.instance then
      -- K.instance:set_user_vars { NVIM_ATTACHED = vim.fn.getpid() }
      K.instance:defer_till_open { "set_user_vars", { { NVIM_ATTACHED = vim.fn.getpid() } } }
      K.setup = function(_) return K end
      kutils.staticify(K.instance, K)
    end

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
      attach_to_win = id,
    }, type(cfg) == "table" and cfg or cfg(t)))
  end
  return terms
end

return K
