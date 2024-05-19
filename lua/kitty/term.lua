-- REF: https://sw.kovidgoyal.net/kitty/remote-control/
local api = vim.api
local system = vim.system
local titles = {}
local kutils = require "kitty.utils"
local Kitty = {
  title = "Kitty.nvim",
  listen_on = kutils.port_from_pid,
  default_launch_location = "tab",
  is_tab = false,
  launch_counter = 0,
  from_id = 1,
  kitty_client_exe = kutils.kitten(),
  send_text_hooks = {},
}

function Kitty:build_api_command(cmd, args)
  return kutils.build_api_command(self.listen_on, self.match_arg, self.kitty_client_exe, cmd, args)
end
function Kitty:api_command(cmd, args, system_opts, on_exit)
  return kutils.api_command(self.listen_on, self.match_arg, self.kitty_client_exe, cmd, args, system_opts, on_exit)
end
function Kitty:api_command_blocking(cmd, args, system_opts, on_exit)
  return kutils.api_command_blocking(self.listen_on, self.match_arg, self.kitty_client_exe, cmd, args, system_opts)
end
local from_api_command = function(name, default_args)
  default_args = default_args or {}
  vim.validate {
    name = { name, "string" },
  }
  return function(self, args, system_opts, on_exit)
    if type(args) ~= "table" then args = { args } end
    args = vim.list_extend(args or {}, default_args)
    return self:api_command(name, args, system_opts, on_exit)
  end
end
local from_api_command_blocking = function(name, default_args)
  default_args = default_args or {}
  vim.validate {
    name = { name, "string" },
  }
  return function(self, args, system_opts)
    if type(args) ~= "table" then args = { args } end
    args = vim.list_extend(args or {}, default_args)
    return self:api_command_blocking(name, args, system_opts)
  end
end

function Kitty:append_match_args(args, use_window_id, flag)
  return kutils.append_match_args(args, self.match_arg, use_window_id, flag)
end

function Kitty:close_on_leave(evt, wait)
  vim.schedule(function()
    local close
    api.nvim_create_autocmd(evt or "VimLeavePre", {
      callback = function()
        -- vim.schedule(function()
        vim.notify("Closing Kitty: " .. self.title, vim.log.levels.INFO)
        close = self:close()
        if wait then close:wait() end
        -- end)
      end,
    })
    if not evt or not wait then
      api.nvim_create_autocmd(evt or "VimLeave", {
        callback = function()
          -- vim.schedule(function()
          close:wait() -- FIXME: unnecessary?
          -- end)
        end,
      })
    end
  end)
end

Kitty.close = from_api_command "close-window"
Kitty.close_tab = from_api_command "close-tab"
Kitty.close_blocking = from_api_command_blocking "close-window"

-- TODO: make this smarter?
local function open_if_not_yet(fn)
  return function(self, args, system_opts, on_exit)
    if self.is_opened then
      self:focus() -- FIXME: sure about this?
      return
    end

    local handle = { fn(self, args, system_opts, on_exit) }

    self.is_opened = true

    return unpack(handle)
  end
end

function Kitty:reopen(...)
  self.is_opened = false
  return self:open(...)
end
Kitty.open = open_if_not_yet(function(self, args, system_opts, on_exit)
  -- TODO: make this smarter?
  -- self:ls( function(code, _)
  --   if code == 0 then
  --     return
  --   end
  -- end)

  local cmdline = {
    self.kitty_open_exe or "kitty",
    "--listen-on",
    self.listen_on,
    "--override",
    "allow_remote_control=yes",
  }
  local env = kutils.nvim_env_injections()
  if env then
    for k, v in pairs(env) do
      cmdline[#cmdline + 1] = "--override"
      cmdline[#cmdline + 1] = "env=" .. k .. "=" .. v
    end
  end
  if self.title then
    cmdline[#cmdline + 1] = "--title"
    cmdline[#cmdline + 1] = self.title
  end
  if self.focus_on_open then
    -- TODO: Sub.focus_on_open and "" or "--dont-take-focus",
  end
  if self.open_cwd then
    cmdline[#cmdline + 1] = "--directory"
    cmdline[#cmdline + 1] = self.open_cwd
  end
  if self.keep_open then cmdline[#cmdline + 1] = "--hold" end
  if not self.dont_detach then cmdline[#cmdline + 1] = "--detach" end
  if self.open_session then
    cmdline[#cmdline + 1] = "--session"
    cmdline[#cmdline + 1] = self.open_session
  end
  if self.open_window_as then
    cmdline[#cmdline + 1] = "--start-as"
    cmdline[#cmdline + 1] = self.open_window_as
  end
  if self.open_wm_class then
    if type(self.open_wm_class) == "string" then
      cmdline[#cmdline + 1] = "--class"
      cmdline[#cmdline + 1] = self.open_wm_class
    else
      cmdline[#cmdline + 1] = "--class"
      cmdline[#cmdline + 1] = self.open_wm_class.class or self.open_wm_class[1]
      cmdline[#cmdline + 1] = "--name"
      cmdline[#cmdline + 1] = self.open_wm_class.name or self.open_wm_class[2]
    end
  end
  if self.open_layout then
    cmdline[#cmdline + 1] = "--override"
    cmdline[#cmdline + 1] = "enabled_layouts='" .. self.open_layout .. ",*'"
  end
  if args then
    vim.list_extend(cmdline, args)
  elseif self.launch_cmd then
    if type(self.launch_cmd) == "string" then self.launch_cmd = { self.launch_cmd } end
    vim.list_extend(cmdline, self.launch_cmd)
  end

  -- TODO: use jobstart?
  local handle = system(
    cmdline,
    vim.tbl_extend("keep", system_opts, {
      -- TODO: handle some things?
    }),
    function(out)
      self.is_opened = false

      if out.code == 0 then
        if not self.dont_close_on_leave then self:close_on_leave() end
      end

      if on_exit then on_exit(out) end
    end
  )

  -- self:set_match_arg_from_pid(pid) -- FIXME: this doesn't work?
  self:set_match_arg_from_id(1)

  return handle
end)

Kitty.to_arg = setmetatable({}, {
  __call = function(t, k, v)
    local ret = "--" .. k:gsub("_", "-") .. "=" .. v
    return ret
  end,
  __index = function(t, k)
    local ret = "--" .. k:gsub("_", "-")
    return ret
  end,
})

local where_locations = { "after", "before", "first", "hsplit", "last", "neighbor", "split", "vsplit" }
function Kitty:sub_window(o, where)
  if where == true then where = self.default_launch_location end
  where = where or self.default_launch_location

  o = o or {}
  o.listen_on = self.listen_on
  if o.title == nil or o.title == self.title then
    o.title = self.title .. "-" .. self.launch_counter
    self.launch_counter = self.launch_counter + 1
  end
  o.attach_to_win = false
  o.from_id = nil
  o.is_opened = false
  vim.tbl_extend("keep", o, {
    default_launch_location = self.default_launch_location,
  })

  -- TODO: should this really be a subclass? not all properties should be inherited... should any at all?
  local Sub = self:new(o)
  Sub:set_match_arg { -- TODO: using title is kinda brittle, maybe
    title = Sub.title,
  }

  local open_cwd = Sub.open_cwd
  if open_cwd == nil or open_cwd == "" then open_cwd = "current" end
  if vim.tbl_contains(where_locations, where, {}) then
    Sub.split_location = where
    where = "window"
  end
  local launch_args = {
    "--window-title",
    Sub.title,
    "--tab-title",
    Sub.title,
    "--type",
    where,
    "--cwd",
    open_cwd,
  }
  if not Sub.dont_copy_env then launch_args[#launch_args + 1] = "--copy-env" end
  local env = kutils.nvim_env_injections(Sub)
  kutils.env_injections(env, launch_args)
  kutils.env_injections(Sub.env_injections, launch_args)
  if not Sub.focus_on_open then launch_args[#launch_args + 1] = "--dont-take-focus" end
  if Sub.keep_open then launch_args[#launch_args + 1] = "--hold" end
  if Sub.split_location then
    launch_args[#launch_args + 1] = "--location"
    launch_args[#launch_args + 1] = Sub.split_location
  end
  if Sub.stdin_source then
    launch_args[#launch_args + 1] = "--stdin-source"
    launch_args[#launch_args + 1] = Sub.stdin_source
  end

  Sub.open = open_if_not_yet(function(sub, args, system_opts, on_exit)
    system_opts = system_opts or {}
    if not args and sub.launch_cmd then args = sub.launch_cmd end
    if type(args) == "string" then args = { args } end
    local cmd = vim.list_extend({}, launch_args)
    if args then cmd = vim.list_extend(cmd, args) end

    local handle = self:api_command("launch", cmd, system_opts, function(out)
      if out.code == 0 and out.stdout then
        sub:set_match_arg_from_id(out.stdout)
      else
        vim.notify("Error launching Kitty subwindow", vim.log.levels.ERROR, {})
        vim.print(out.stderr)
      end
      if on_exit then on_exit(out) end
    end)
    return handle
  end)

  Sub.launch_where = where
  return Sub
end

function Kitty:launch(o, where, args, system_opts, on_exit)
  local Sub = self:sub_window(o, where)
  local open_cmd = Sub:open(args, system_opts, on_exit)
  return Sub, open_cmd
end

--https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitty-launch-type
function Kitty:new_tab(o, args)
  if type(o) == "string" and args == nil then args = { o } end
  return self:launch(o, "tab", args)
end
function Kitty:new_window(o, args)
  if type(o) == "string" and args == nil then args = { o } end
  return self:launch(o, "window", args)
end
for _, loc in ipairs(where_locations) do
  Kitty["new_win_" .. loc] = function(self, o, args)
    self:goto_layout "splits"
    if type(o) == "string" and args == nil then args = { o } end
    return self:launch(o, loc, args)
  end
end
function Kitty:new_os_window(o, args)
  if type(o) == "string" and args == nil then args = { o } end
  return self:launch(o, "os-window", args)
end
function Kitty:new_overlay(o, args)
  if type(o) == "string" and args == nil then args = { o } end
  return self:launch(o, "overlay", args)
end

function Kitty:goto_layout(name, system_opts, on_exit)
  if name == "last-used-layout" then return self:api_command("last-used-layout", {}, system_opts, on_exit) end

  return self:api_command("goto-layout", { name }, system_opts, on_exit)
end
function Kitty:last_used_layout(system_opts, on_exit) return self:goto_layout("last-used-layout", system_opts, on_exit) end
Kitty.run_kitten = from_api_command "kitten"

function Kitty:focus(system_opts, on_exit)
  local default_args = {}
  return self:api_command(self.is_tab and "focus-tab" or "focus-window", default_args, system_opts, on_exit)
end
Kitty.resize_os_window = from_api_command "resize-os-window"
Kitty.resize_window = from_api_command "resize-window"
Kitty.reset_layout = from_api_command("resize-window", { "--axis", "reset" })
Kitty.toggle_fullscreen = from_api_command("resize-os-window", { "--action", "toggle-fullscreen" })
Kitty.toggle_maximized = from_api_command("resize-os-window", { "--action", "toggle-maximized" })
function Kitty:toggle_fullscreen(system_opts, on_exit) self:resize_os_window({}, system_opts, on_exit) end
-- target can be:
--  - new-tab
--  - new-window (os window)
--  - this-tab (this = current_win)
--  - string to pass to --target-tab (see kitty docs)
--  - Kitty terminal object whose tab will be used
--  - TODO: {new_in = Kitty terminal object}
function Kitty:detach(target, system_opts, on_exit)
  local built_args = {}
  if self.is_tab then
    built_args = { "detach-tab" }
    if target ~= nil and target ~= "new" then vim.list_extend(built_args, { "--target-tab", target }) end
  else
    -- Pass 'new' for new tab
    -- echo hello
    if target == "new-window" then
      -- Specifically no --target-tab
    elseif target ~= nil then
      if type(target) == "string" then
        if target == "new-tab" then target = "new" end
        if target == "this-tab" then pcall(function() target = require("kitty.current_win").instance end) end
      end
      if type(target) == "string" then
        vim.list_extend(built_args, { "--target-tab", target }) -- target should be SomeTab.match_arg
      else
        if target.new_in then
          -- TODO: new tab in that window
          target.new_in:append_match_args(built_args, true, "--target-tab")
        else
          target:append_match_args(built_args, true, "--target-tab")
        end
      end
    end
  end
  return self:api_command("detach-window", built_args, system_opts, on_exit)
end
Kitty.move = Kitty.detach -- Alternate name since detach actually allows moving window/tab

function Kitty:send_key(keys, system_opts, on_exit)
  -- TODO: map from neovim to kitty
  return self:api_command("send-key", type(keys) == "table" and keys or { keys }, system_opts, on_exit)
end
function Kitty:send(text, system_opts, on_exit)
  local sep = self.text_sep or "\\r"
  local send_text = text
  local bracketed_paste = self.bracketed_paste
  local prefix, suffix = self.send_text_prefix, self.send_text_suffix
  if type(text) == "table" and not vim.islist(text) then
    if text.sep then sep = text.sep end
    if text.bracketed_paste ~= nil then bracketed_paste = text.bracketed_paste end
    if text.prefix then prefix = text.prefix end
    if text.suffix then suffix = text.suffix end

    if text.selection then
      if text.selection == true then text.selection = api.nvim_get_mode().mode end
      send_text = kutils.get_selection(text.selection)
    elseif text.text then
      send_text = text.text
    elseif text[1] then
      send_text = text[1]
    end
  end

  if type(send_text) == "table" and vim.islist(send_text) then send_text = table.concat(send_text, sep) end

  if bracketed_paste ~= nil then
    prefix = prefix or ""
    suffix = suffix or ""
    local csi = kutils.unkeycode_map.CSI
    prefix = prefix .. csi .. "200~"
    suffix = csi .. "201~" .. suffix
  end
  if prefix ~= nil then send_text = prefix .. send_text end
  if suffix ~= nil then send_text = send_text .. suffix end
  local send = { "--", send_text }

  for _, hook in pairs(self.send_text_hooks) do
    local new, done = hook(send)
    if new ~= nil then send = new end
    if done then break end
  end

  return self:api_command("send-text", send, system_opts, on_exit)
end
function Kitty:cmd(text, system_opts, on_exit)
  if type(text) == "string" then
    text = { text = text, suffix = "\r" }
  elseif type(text) == "table" then
    text.suffix = "\r"
  end
  return self:send(text, system_opts, on_exit)
end
-- Mirror the vim.system API
function Kitty:vimsystem(opts, cmd, opts, on_exit)
  opts = vim.tbl_extend("force", {
    launch = false,
  }, opts or {})
  if opts.launch then
    vim.notify "Launch Unimplemented"
  else
    if type(cmd) == "string" then cmd = { cmd } end
    if opts.cwd then
      table.insert(cmd, 0, "cd")
      table.insert(cmd, 0, opts.cwd)
      table.insert(cmd, 0, "&&")
    end
    if opts.stdin then
    end
    if opts.stdout then
    end
    if opts.stderr then
    end

    -- TODO: escaping???
    self:cmd(vim.iter(cmd):join " ", {}, on_exit)
  end
end
function Kitty:send_operator(args, system_opts, on_exit)
  args = args or {}
  Kitty.__send_operatorfunc = function(type)
    self:send(
      vim.tbl_extend("keep", {
        selection = args.type or type,
      }, args),
      system_opts,
      on_exit
    )
  end
  vim.go.operatorfunc = "v:lua.require'kitty.term'.__send_operatorfunc"
  return "g@" .. (args.range or "")
end

function Kitty:paste(text, system_opts, on_exit)
  if type(text) == "string" then
    text = { text = text, bracketed_paste = true }
  elseif type(text) == "table" then
    text.bracketed_paste = true
  end
  return self:send(text, system_opts, on_exit)
end
function Kitty:send_file(from_file, system_opts, on_exit)
  return self:api_command("send-text", {
    "--from-file",
    (from_file or api.nvim_buf_get_name(0)),
  }, system_opts, on_exit)
end

-- https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitty-get-text-extent
-- all, first_cmd_output_on_screen, last_cmd_output, last_non_empty_output,
-- last_visited_cmd_output, screen, selection
function Kitty:get_text(extent, args, system_opts, on_exit)
  return self:api_command(
    "get-text",
    vim.list_extend({ "--extent", (extent or "screen") }, args or {}),
    system_opts,
    on_exit
  )
end
function Kitty:get_text_to_buffer(extent, args, system_opts, on_exit)
  return self:get_text(
    extent,
    args,
    system_opts,
    vim.schedule_wrap(function(out)
      if out.code == 0 then
        if out.stdout then
          local b, l = kutils.dump_to_buffer(nil, out.stdout)
          out.lines = l
          on_exit(out)
        end
      else
        error("Error getting text: " .. out.stderr)
      end
    end)
  )
end
function Kitty:get_text_to_qflist(extent, args, system_opts, on_exit)
  return self:get_text(
    extent,
    args,
    system_opts,
    vim.schedule_wrap(function(out)
      if out.code == 0 then
        out.lines = vim.split(out.stdout, "\n")
        vim.fn.setqflist(nil, nil, { lines = out.lines })
        on_exit(out)
      else
        error("Error getting text: " .. out.stderr)
      end
    end)
  )
end
function Kitty:get_selection(reg)
  local cb
  if reg == nil or type(reg) == "string" or reg == true then
    if type(reg) ~= "string" or reg == "register" then reg = vim.v.register end
    cb = function(data) vim.fn.setreg(reg or '"', data:sub(1, -2)) end
  elseif type(reg) == "function" then
    cb = reg
  end
  cb = vim.schedule_wrap(cb)
  self:get_text("selection", {}, {}, function(out)
    if out.code == 0 then cb(out.stdout) end
  end)
end

function Kitty:scroll(opts, system_opts, on_exit)
  if type(opts) == "string" then opts = { amount = opts } end
  local amount = opts.amount
  if not amount then
    if opts.till_end then
      amount = "end"
    elseif opts.till_start then
      amount = "start"
    elseif opts.up then
      amount = tostring(opts.up) .. "-"
    elseif opts.down then
      amount = tostring(opts.down) .. "+"
    elseif opts.prompts then
      if opts.prompts == "top" then
        return self:api_command("action", { "scroll_prompt_to_top" }, system_opts, on_exit)
      elseif opts.prompts == "bottom" then
        return self:api_command("action", { "scroll_prompt_to_bottom" }, system_opts, on_exit)
      else
        return self:api_command("action", { "scroll_to_prompt " .. tostring(opts.prompts) }, system_opts, on_exit)
      end
    end
  end
  return self:api_command("scroll", { amount }, system_opts, on_exit)
end
function Kitty:scroll_up(lines, system_opts, on_exit) return self:scroll({ up = lines }, system_opts, on_exit) end
function Kitty:scroll_down(lines, system_opts, on_exit) return self:scroll({ down = lines }, system_opts, on_exit) end

Kitty.signal_child = from_api_command "signal-child"

local json_to_buffer
function Kitty:ls_match(match, cb, on_exit)
  json_to_buffer = json_to_buffer or require("kitty.ls").json_to_buffer
  cb = cb or json_to_buffer or vim.print
  local args = { "--all-env-vars" }
  if match == true or match == nil then
    kutils.append_match_args(args, self.match_arg, "ls")
  elseif match == "tab" then
    kutils.append_match_args(args, self.match_arg, "ls", "--match-tab")
  elseif type(match) == "string" then
    if vim.startswith(match, "tab:") then
      args[#args + 1] = "--match-tab"
      args[#args + 1] = match:sub(5)
    else
      args[#args + 1] = "--match"
      args[#args + 1] = match
    end
  end
  return self:api_command("ls", args, {}, function(out)
    if out.code == 0 then
      local data = out.stdout
      local decoded = vim.json.decode(data, {})
      cb(decoded, data)
      if on_exit then on_exit(out) end
    end
  end)
end
function Kitty:ls(cb, on_exit)
  return self:ls_match(false, cb, on_exit)
end
Kitty.font_size = from_api_command "set-font-size"
Kitty.font_up = from_api_command("set-font-size", { "--", "+1" })
Kitty.font_down = from_api_command("set-font-size", { "--", "-1" })
Kitty.set_spacing = from_api_command "set-spacing"
Kitty.set_window_title = from_api_command("set-window-title", { "--temporary" })

-- Run a mappable action
Kitty.action = from_api_command "action"
-- Run a kitten
Kitty.kitten = from_api_command "kitten"
-- TODO: helpers for specific actions and kittens

Kitty.reload_config = from_api_command "load-config"

Kitty.select_window = from_api_command("select-window", { "--reactivate-prev-tab" })

-- TODO: nice API for this
Kitty.create_marker = from_api_command "create-marker"
Kitty.remove_marker = from_api_command "remove-marker"

-- opts: {
--     type: string | table,
--     yank: string,
--     where: string,
--     program: string,
--     launch: string,
--     regex: string,
--     multiple: boolean | string,
--     ascending: boolean,
--     alphabet: string,
--     args: any[],
-- }
local customize_hints_processing = setmetatable({}, {
  __index = function(t, k)
    t[k] = vim.api.nvim_get_runtime_file("kitty/customize_hints/" .. k .. ".py", false)[1]
    return k
  end,
})
local sh = setmetatable({}, {
  __index = function(t, k)
    local v = vim.api.nvim_get_runtime_file("sh/kitty/" .. k .. ".sh", false)[1]
    t[k] = v
    return v
  end,
})
function Kitty:sh(name, launch)
  local shcmd = "sh " .. sh[name] .. " " .. vim.fn.getpid()
  if launch then
    return "launch --type=background " .. shcmd
  else
    return shcmd
  end
end
function Kitty:wakeup(launch) return self:sh("wakeup", launch) end
function Kitty:hints(opts, system_opts, on_exit)
  opts = opts or {}
  -- TODO: does - paste to this terminal or that?
  local args = {
    "hints",
  }
  if not opts.stay_in_terminal then
    args[#args + 1] = "--program"
    args[#args + 1] = self:wakeup(true)
  end
  -- hash, hyperlink, ip, line, linenum, path, regex, url, word
  if opts.type then
    args[#args + 1] = "--type"
    if type(opts.type) == "string" then
      args[#args + 1] = opts.type or (opts.regex and "regex")
    elseif type(opts.type) == "table" then
      if opts.type.url or opts.type.url_prefixes or opts.type.url_exluded then
        args[#args + 1] = "url"
        local prefixes = opts.type.url_prefixes or opts.type.prefixes
        if prefixes then
          args[#args + 1] = "--url-prefixes"
          args[#args + 1] = type(prefixes) == "string" and prefixes or table.concat(prefixes, ",")
        end
        if opts.type.url_exluded or opts.type.excluded then
          args[#args + 1] = "--url-excluded-characters"
          args[#args + 1] = opts.type.url_exluded or opts.type.excluded
        end
      elseif opts.type.word then
        args[#args + 1] = "word"
        if type(opts.type.word) == "string" then
          args[#args + 1] = "--word-characters"
          args[#args + 1] = opts.type.word -- TODO: get this from vim definition?
        end
      end
    end
  end

  local function yank_to(output, paste)
    local reg
    if type(output) == "function" then
      local cb = output
      output = "@"
      local old = vim.fn.getreg "+"
      vim.api.nvim_create_autocmd("FocusGained", {
        group = vim.api.nvim_create_augroup("kitty-hints-focus-gained", { clear = true }),
        pattern = "*",
        once = true,
        callback = function()
          local v = vim.fn.getreg "+"
          vim.fn.setreg("+", old)
          cb(v)
        end,
      })
    else
      if output == true then output = "register" end
      local on_focus_gained
      if output == "register" then output = vim.v.register end
      if not vim.tbl_contains({ "@", "+", "*" }, output) and #output == 1 then
        output = "@"
        local old = vim.fn.getreg "+"
        on_focus_gained = function()
          vim.fn.setreg('"', vim.fn.getreg "+")
          vim.fn.setreg("+", old)
        end
        reg = '"'
      elseif output == "+" or output == "clipboard" or output == "@" then
        output = "@"
        reg = "+"
      elseif output == "selection" then
        output = "*"
        reg = "*"
      else
        error("Invalid output register for yank/paste: " .. output)
      end
      if on_focus_gained or paste then
        vim.api.nvim_create_autocmd("FocusGained", {
          group = vim.api.nvim_create_augroup("kitty-hints-focus-gained", { clear = true }),
          pattern = "*",
          once = true,
          callback = function()
            on_focus_gained()
            if paste then vim.schedule(function() vim.feedkeys('"' .. reg .. "p", "m") end) end
          end,
        })
      end
    end
    args[#args + 1] = "--program"
    args[#args + 1] = output
  end
  local function program(prg, default)
    if prg.yank or prg.paste then
      vim.print(prg)
      yank_to(prg.yank or prg.paste, not not prg.paste)
    else
      local where = prg.where or "self"
      if prg.type == "linenum" then
        args[#args + 1] = "--linenum-action"
        args[#args + 1] = where
        if prg.program then args[#args] = where .. " " .. (prg.program or vim.v.argv[0]) end
      else
        if prg.program then
          args[#args + 1] = "--program"
          args[#args + 1] = type(prg.program) == "string" and prg.program or "default"
        elseif prg.launch then
          args[#args + 1] = "--program"
          args[#args + 1] = "launch --type=" .. where .. " " .. prg.launch
        elseif default ~= false then
          args[#args + 1] = "--program"
          args[#args + 1] = "@"
        end
      end
    end
    if prg.extra_programs then
      program(prg.extra_programs, false)
      for _, program in ipairs(prg.extra_programs) do
        program(program, false)
      end
    end
  end
  program(opts)
  -- for linenum must have named groups: path and line
  if opts.regex then
    args[#args + 1] = "--regex"
    args[#args + 1] = opts.regex
  end
  if opts.multiple then args[#args + 1] = "--multiple" end
  if type(opts.multiple) == "string" then -- any or space,newline,empty,json,auto
    args[#args + 1] = "--multiple-joiner"
    args[#args + 1] = opts.multiple
  end
  if opts.ascending then args[#args + 1] = "--ascending" end
  if opts.alphabet then
    args[#args + 1] = "--alphabet"
    args[#args + 1] = opts.alphabet
  end
  if opts.args then vim.list_extend(args, opts.args) end
  if opts.custom_py then
    args[#args + 1] = "--customize-processing"
    args[#args + 1] = customize_hints_processing[opts.custom_py]
  end
  if opts.custom_proc then
    args[#args + 1] = "--customize-processing"
    args[#args + 1] = opts.custom_proc
  end

  self:api_command("kitten", args, system_opts, function(out)
    if out.code == 0 then self:focus({}, on_exit) end
  end)
end

function Kitty:set_match_arg(arg) self.match_arg = arg end
function Kitty:set_match_arg_from_id(id) self:set_match_arg { id = id } end
function Kitty:set_match_arg_from_pid(pid)
  -- FIXME: I dont think pid match_arg works
  self:set_match_arg { pid = pid }
end
function Kitty:universal() return self:new { match_arg = "" } end
function Kitty:recent(i) return self:new { match_arg = "recent:" .. (i or 0) } end
function Kitty:current_tab() return self:new { is_tab = self.is_tab } end
-- TODO: Remote control: Allow matching by neighbor of active window. Useful for navigation plugins like vim-kitty-navigator
-- TODO: matching on set-user-var

function Kitty:new(o)
  if o == nil then return Kitty:new(self) end
  o = o or {}
  o.send_text_hooks = o.send_text_hooks and vim.list_extend(o.send_text_hooks, self.send_text_hooks)
  setmetatable(o, self)
  self.__index = self

  -- Setup stuff
  if type(o.listen_on) == "function" then o.listen_on = o.listen_on() end
  if o.attach_to_win then
    o.listen_on = kutils.current_win_listen_on()
    o.from_id = o.attach_to_win
    if o.attach_to_win == true or o.attach_to_win == "current" then o.from_id = kutils.current_win_id() end
    o.is_opened = true
    o.open = function(...) end
    o.attach_to_win = nil
  end
  if o.from_id then
    o:set_match_arg_from_id(o.from_id)
    o.from_id = nil
  end
  -- Warn about Duplicate window titles
  -- for _, v in ipairs(titles) do
  --   if o.title == v then vim.notify("Kitty Window title already used: " .. o.title, vim.log.WARN, {}) end
  -- end
  titles[#titles + 1] = o.title

  return o
end

-- TODO: create a user command that allows interacting with the terminal
function Kitty:user_command(name)
  api.nvim_create_user_command(name, function(args)
    if args.fargs[1]:sub(1, 1) == "+" then
      self[args.fargs[1]:sub(2)](self, vim.list_slice(args.fargs, 2, nil))
    else
      self:send(args.args .. "\\r")
    end
  end, { nargs = "?" })
end

Kitty.setup_make = require("kitty.make").setup
Kitty.setup_repl = require("kitty.repl").setup

return Kitty
