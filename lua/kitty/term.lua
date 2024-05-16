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
  kitty_client_exe = "kitty", -- Can use kitten instead?
  send_text_hooks = {},
}

function Kitty:build_api_command(cmd, args)
  return kutils.build_api_command(self.listen_on, self.match_arg, self.kitty_client_exe, cmd, args)
end
function Kitty:api_command(cmd, args, system_opts, on_exit)
  return kutils.api_command(self.listen_on, self.match_arg, self.kitty_client_exe, cmd, args, system_opts, on_exit)
end
function Kitty:api_command_blocking(cmd, args) kutils.api_command_blocking(self.listen_on, self.match_arg, cmd, args) end
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
local from_api_command_blocking = function(name)
  return function(self, args)
    if type(args) ~= "table" then args = { args } end
    return self:api_command_blocking(name, args)
  end
end

function Kitty:append_match_args(args, use_window_id, flag)
  return kutils.append_match_args(args, self.match_arg, use_window_id, flag)
end

function Kitty:close_on_leave(evt)
  vim.schedule(function()
    api.nvim_create_autocmd(evt or "VimLeavePre", {
      callback = function()
        -- vim.schedule_wrap(function()
        vim.notify("Closing Kitty: " .. self.title, vim.log.levels.INFO)
        self:close_blocking()
        -- end)
      end,
    })
  end)
end

Kitty.close = from_api_command "close-window"
Kitty.close_tab = from_api_command "close-tab"
Kitty.close_blocking = from_api_command_blocking "close-window"

-- TODO: make this smarter?
local function open_if_not_yet(fn)
  return function(self, args, system_opts, on_exit)
    if self.is_opened then
      self:focus()
      return
    end

    local handle, pid = fn(self, args, system_opts, on_exit)
    -- TODO: get the window/tab id

    self.is_opened = true

    return handle, pid
  end
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
    function(code, signal)
      self.is_opened = false

      if code == 0 then
        if not self.dont_close_on_leave then self:close_on_leave() end
      end

      if on_exit then on_exit(code, signal) end
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
  Sub:set_match_arg { -- TODO: using title is kinda brittle
    title = Sub.title,
  }

  local open_cwd = Sub.open_cwd
  if open_cwd == nil or open_cwd == "" then open_cwd = "current" end
  if vim.tbl_contains(where_locations, where, {}) then
    Sub.split_location = where
    where = "window"
  end
  Sub.launch_args = {
    "--window-title",
    Sub.title,
    "--tab-title",
    Sub.title,
    "--type",
    where,
    "--cwd",
    open_cwd,
  }
  local env = kutils.nvim_env_injections(Sub)
  if env then
    for k, v in pairs(env) do
      Sub.launch_args[#Sub.launch_args + 1] = "--env"
      Sub.launch_args[#Sub.launch_args + 1] = k .. "=" .. v
    end
  end
  if Sub.env_injections then
    for k, v in pairs(Sub.env_injections) do
      Sub.launch_args[#Sub.launch_args + 1] = "--env"
      Sub.launch_args[#Sub.launch_args + 1] = k .. "=" .. v
    end
  end
  if not Sub.focus_on_open then Sub.launch_args[#Sub.launch_args + 1] = "--dont-take-focus" end
  if Sub.keep_open then Sub.launch_args[#Sub.launch_args + 1] = "--hold" end
  if Sub.split_location then
    Sub.launch_args[#Sub.launch_args + 1] = "--location"
    Sub.launch_args[#Sub.launch_args + 1] = Sub.split_location
  end
  if Sub.stdin_source then
    Sub.launch_args[#Sub.launch_args + 1] = "--stdin-source"
    Sub.launch_args[#Sub.launch_args + 1] = Sub.stdin_source
  end
  if not Sub.dont_copy_env then Sub.launch_args[#Sub.launch_args + 1] = "--copy-env" end

  Sub.open = open_if_not_yet(function(sub, args, system_opts, on_exit)
    system_opts = system_opts or {}
    if not args and sub.launch_cmd then args = sub.launch_cmd end
    if type(args) == "string" then args = { args } end
    if args then sub.launch_args = vim.list_extend(sub.launch_args, args) end

    local handle = self:api_command(
      "launch",
      sub.launch_args,
      vim.tbl_extend("keep", {
        stdout = function(err, data)
          if err then vim.notify("Error launching Kitty: " .. err, vim.log.levels.ERROR, {}) end
          if data then sub:set_match_arg_from_id(data) end
        end,
      }, system_opts),
      on_exit
    )
    return handle
  end)

  return Sub
end
function Kitty:launch(o, where, args, system_opts, on_exit)
  local Sub = self:sub_window(o, where)
  Sub:open(args, system_opts, on_exit)
  return Sub
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
        target:append_match_args(built_args, true, "--target-tab")
      end
    end
  end
  return self:api_command("detach-window", built_args, system_opts, on_exit)
end
Kitty.move = Kitty.detach -- Alternate name since detach actually allows moving window/tab

-- function Kitty:send_file()
--   local filename = vim.fn.expand "%:p"
--   local payload = ""
--   local lines = vim.fn.readfile(filename)
--   for _, line in ipairs(lines) do
--     payload = payload .. line .. "\n"
--   end
--   self:send(payload)
-- end

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

local termcodes = api.nvim_replace_termcodes
local function t(k) return termcodes(k, true, true, true) end
function Kitty:send_key(text)
  print(text)
  vim.notify("Unimplemented", vim.log.levels.ERROR, {})
end

-- https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitty-get-text-extent
function Kitty:get_text_stream(extent, args, system_opts, on_exit)
  return self:api_command(
    "get-text",
    vim.list_extend({ "--extent", (extent or "screen") }, args or {}),
    system_opts,
    on_exit
  )
end
function Kitty:get_text(extent, args, on_exit)
  local buffer = {}
  return self:get_text_stream(extent, args, {
    stdout = function(err, data)
      if err then error(err) end
      if data then buffer[#buffer + 1] = data end
    end,
  }, function(code, signal)
    if code == 0 then
      on_exit(table.concat(buffer, ""), code, signal)
    else
      on_exit(false, code, signal, buffer)
    end
  end)
end
function Kitty:get_text_to_buffer(extent, args, on_exit)
  local bufnr
  return self:get_text_stream(extent, args, {
    stdout = function(err, data)
      if not bufnr then
        vim.cmd.split()
        vim.cmd.enew()
        bufnr = vim.api.nvim_get_current_buf()
      end
      vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, vim.split(data, "\n"))
    end,
  }, on_exit)
end
function Kitty:get_selection(reg)
  local cb
  if reg == nil or type(reg) == "string" then
    cb = function(data) vim.fn.setreg(reg or '"', data) end
  elseif type(reg) == "function" then
    cb = reg
  end
  cb = vim.schedule_wrap(cb)
  self:get_text("selection", {}, cb)
end

function Kitty:scroll(opts, system_opts, on_exit)
  local amount = opts.amount
  if not amount and opts.till_end then amount = "end" end
  if not amount and opts.till_start then amount = "start" end
  if not amount and opts.up then amount = tostring(opts.up) .. "-" end
  if not amount and opts.down then amount = tostring(opts.down) .. "+" end
  return self:api_command("scroll", {
    amount,
  }, system_opts, on_exit)
end
function Kitty:scroll_up(opts, system_opts, on_exit)
  return self:scroll(vim.list_extend(opts or {}, { up = 1 }), system_opts, on_exit)
end
function Kitty:scroll_down(opts, system_opts, on_exit)
  return self:scroll(vim.list_extend(opts or {}, { down = 1 }), system_opts, on_exit)
end
Kitty.signal_child = from_api_command "signal-child"
local json_to_buffer = require("kitty.ls").json_to_buffer
function Kitty:ls(cb, on_exit)
  cb = cb or json_to_buffer or vim.print
  return self:api_command("ls", { "--all-env-vars" }, {
    stdout = function(err, data)
      if err then vim.notify(err, vim.log.levels.ERROR) end
      if data then
        local decoded = vim.json.decode(data, {})
        cb(decoded, data)
      end
    end,
  }, on_exit)
end
Kitty.font_size = from_api_command "set-font-size"
Kitty.font_up = from_api_command("set-font-size", { "--", "+1" })
Kitty.font_down = from_api_command("set-font-size", { "--", "-1" })
Kitty.set_spacing = from_api_command "set-spacing"
Kitty.set_window_title = from_api_command("set-window-title", { "--temporary" })

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
