-- https://sw.kovidgoyal.net/kitty/remote-control/
local titles = {}
local Kitty = {
  title = "Kitty.nvim",
  listen_on = "unique_port",
  default_launch_location = "tab",
  is_tab = false,
  launch_counter = 0,
  from_id = 1,
}
-- Use this to control the window that neovim is inside
function Kitty.current_win_listen_on()
  return vim.env.KITTY_LISTEN_ON
end
function Kitty.current_win_id()
  return vim.env.KITTY_WINDOW_ID
end
local unique_listen_on_counter = 0
function Kitty.port_from_pid(prefix)
  unique_listen_on_counter = unique_listen_on_counter + 1
  return (prefix or "unix:/tmp/kitty.nvim-") .. vim.fn.getpid() .. unique_listen_on_counter
end

function Kitty:build_api_command(cmd, args_)
  local args = { "@", "--to", self.listen_on, cmd }
  self:append_match_args(args)
  args = vim.list_extend(args, args_ or {})
  return args
end
function Kitty:api_command(cmd, args_, on_exit, stdio)
  return vim.loop.spawn("kitty", {
    args = self:build_api_command(cmd, args_),
    stdio = stdio,
  }, function(code, signal)
    local stdin, stdout, stderr = unpack(stdio or { nil, nil, nil })
    if stdin then
      stdin:close()
    end
    if stdout then
      stdout:read_stop()
      stdout:close()
    end
    if stderr then
      stderr:read_stop()
      stderr:close()
    end

    if on_exit then
      on_exit(code, signal)
    end
  end)
end
function Kitty:api_command_blocking(cmd, args_)
  local cmdline = self:build_api_command(cmd, args_)
  cmdline = { "kitty", unpack(cmdline) }
  vim.fn.system(cmdline)
end
local from_api_command = function(name, default_args)
  default_args = default_args or {}
  vim.validate {
    name = { name, "string" },
  }
  return function(self, args, on_exit, stdio)
    if type(args) ~= "table" then
      args = { args }
    end
    args = vim.list_extend(args or {}, default_args)
    return self:api_command(name, args, on_exit, stdio)
  end
end
local from_api_command_blocking = function(name)
  return function(self, args)
    if type(args) ~= "table" then
      args = { args }
    end
    return self:api_command_blocking(name, args)
  end
end
function Kitty:append_match_args(args)
  if self.match_arg and self.match_arg ~= "" then
    vim.list_extend(args, { "--match", self.match_arg })
  end
  return args
end

function Kitty:close_on_leave(evt)
  -- FIXME: this doesn't work
  vim.api.nvim_create_autocmd(evt or "VimLeavePre", {
    callback = function()
      print "bye bye kitty!"
      self:close_blocking()
    end,
  })
end
Kitty.close = from_api_command "close-window"
Kitty.close_tab = from_api_command "close-tab"
Kitty.close_blocking = from_api_command_blocking "close-window"

-- TODO: make this smarter?
local function open_if_not_yet(fn)
  return function(self, args, on_exit, stdio)
    self:ls(nil, function(code, _)
      if code == 0 then
        self.is_opened = true
      end
    end)
    if self.is_opened then
      return
    end

    local handle, pid = fn(self, args, on_exit, stdio)
    -- TODO: get the window/tab id

    self.is_opened = true

    return handle, pid
  end
end

Kitty.open = open_if_not_yet(function(self, args_, on_exit, stdio)
  local args = {
    "-o",
    -- "allow_remote_control=yes",
    "env=NVIM_LISTEN_ADDRESS=" .. vim.v.servername,
    "--listen-on",
    self.listen_on,
  }
  if self.title then
    args[#args + 1] = "--title"
    args[#args + 1] = self.title
  end
  if self.focus_on_open then
    -- TODO: Sub.focus_on_open and "" or "--dont-take-focus",
  end
  if self.open_cwd then
    args[#args + 1] = "--directory"
    args[#args + 1] = self.open_cwd
  end
  if self.keep_open then
    args[#args + 1] = "--hold"
  end
  if not self.dont_detach then
    args[#args + 1] = "--detach"
  end
  if self.open_session then
    args[#args + 1] = "--session"
    args[#args + 1] = self.open_session
  end
  if self.open_window_as then
    args[#args + 1] = "--start-as"
    args[#args + 1] = self.open_window_as
  end
  if self.open_wm_class then
    if type(self.open_wm_class) == "string" then
      args[#args + 1] = "--class"
      args[#args + 1] = self.open_wm_class
    else
      args[#args + 1] = "--class"
      args[#args + 1] = self.open_wm_class.class or self.open_wm_class[1]
      args[#args + 1] = "--name"
      args[#args + 1] = self.open_wm_class.name or self.open_wm_class[2]
    end
  end
  vim.list_extend(args, args_)

  local handle, pid = vim.loop.spawn("kitty", {
    args = args,
    stdio = stdio,
  }, on_exit)

  -- self:set_match_arg_from_pid(pid) -- FIXME: this doesn't work?
  self:set_match_arg_from_id(1)

  return handle, pid
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

function Kitty:sub_window(o, where)
  if where == true then
    where = self.default_launch_location
  end
  where = where or self.default_launch_location

  o = o or {}
  print(o.title, self.title)
  if o.title == nil or o.title == self.title then
    o.title = self.title .. "-" .. self.launch_counter
    self.launch_counter = self.launch_counter + 1
  end
  o.attach_to_current_win = false
  o.from_id = nil
  o.is_opened = false

  local Sub = self:new(o)
  Sub:set_match_arg {
    title = Sub.title,
  }

  local open_cwd = Sub.open_cwd
  if open_cwd == nil or open_cwd == "" then
    open_cwd = "current"
  end
  Sub.launch_args = {
    "--window-title",
    Sub.title,
    "--tab-title",
    Sub.title,
    "--type",
    where,
    "--env",
    "NVIM_LISTEN_ADDRESS=" .. vim.v.servername,
    "--cwd",
    open_cwd,
  }
  if not Sub.focus_on_open then
    Sub.launch_args[#Sub.launch_args + 1] = "--dont-take-focus"
  end
  if Sub.keep_open then
    Sub.launch_args[#Sub.launch_args + 1] = "--hold"
  end
  if Sub.split_location then
    Sub.launch_args[#Sub.launch_args + 1] = "--location"
    Sub.launch_args[#Sub.launch_args + 1] = Sub.split_location
  end
  if Sub.stdin_source then
    Sub.launch_args[#Sub.launch_args + 1] = "--stdin-source"
    Sub.launch_args[#Sub.launch_args + 1] = Sub.stdin_source
  end

  Sub.open = open_if_not_yet(function(sub, args_, on_exit, stdio)
    if type(args_) == "string" then
      args_ = { args_ }
    end
    if args_ then
      sub.launch_args = vim.list_extend(sub.launch_args, args_)
    end

    -- vim.notify("Unimplemented", vim.log.levels.ERROR, {})
    local stdout
    if stdio == nil or stdio[2] == nil then
      stdout = vim.loop.new_pipe(false)
      stdio = { nil, stdout, nil }
    else
      stdout = stdio[2]
    end

    local ret = { self:api_command("launch", sub.launch_args, on_exit, stdio) }

    vim.loop.read_start(stdout, function(err, data)
      if err then
        vim.notify("Error launching Kitty: " .. err, vim.log.levels.ERROR, {})
      end
      if data then
        sub:set_match_arg_from_id(data)
      end
    end)
    return unpack(ret)
  end)

  return Sub
end
function Kitty:launch(o, where, args_, on_exit, stdio)
  local Sub = self:sub_window(o, where)
  Sub:open(args_, on_exit, stdio)
  return Sub
end

--https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitty-launch-type
function Kitty:new_tab(o, args)
  return self:launch(o, "tab", args)
end
function Kitty:new_window(o, args)
  return self:launch(o, "window", args)
end
function Kitty:new_hsplit(o, args)
  args = args or {}
  args[#args + 1] = "--location=hsplit"
  return self:launch(o, "window", args)
end
function Kitty:new_vsplit(o, args)
  self:goto_layout "splits"
  args = args or {}
  args[#args + 1] = "--location=vsplit"
  return self:launch(o, "window", args)
end
function Kitty:new_os_window(o, args)
  return self:launch(o, "os-window", args)
end
function Kitty:new_overlay(o, args)
  return self:launch(o, "overlay", args)
end

function Kitty:goto_layout(name, on_exit, stdio)
  if name == "last-used-layout" then
    return self:api_command("last-used-layout", {}, on_exit, stdio)
  end

  return self:api_command("goto-layout", { name }, on_exit, stdio)
end
Kitty.run_kitten = from_api_command "kitten"

function Kitty:focus(on_exit, stdio)
  local args = {}
  return self:api_command(self.is_tab and "focus-tab" or "focus-window", args, on_exit, stdio)
end
Kitty.resize_os_window = from_api_command "resize-os-window"
Kitty.resize_window = from_api_command "resize-window"
Kitty.reset_layout = from_api_command("resize-window", { "--axis", "reset" })
Kitty.toggle_fullscreen = from_api_command("resize-os-window", { "--action", "toggle-fullscreen" })
Kitty.toggle_maximized = from_api_command("resize-os-window", { "--action", "toggle-maximized" })
function Kitty:toggle_fullscreen(on_exit, stdio)
  self:resize_os_window({}, on_exit, stdio)
end
function Kitty:detach(target, on_exit, stdio)
  local args = {}
  if self.is_tab then
    args = { "detach-tab" }
    if target ~= nil and target ~= "new" then
      vim.list_extend(args, { "--target-tab", target })
    end
  else
    -- Pass 'new' for new tab
    if target ~= nil and target ~= "new-window" then
      vim.list_extend(args, { "--target-tab", target }) -- target should be SomeTab.match_arg
    end
  end
  return self:api_command("detach-window", args, on_exit, stdio)
end

-- function Kitty:send_file()
--   local filename = vim.fn.expand "%:p"
--   local payload = ""
--   local lines = vim.fn.readfile(filename)
--   for _, line in ipairs(lines) do
--     payload = payload .. line .. "\n"
--   end
--   self:send(payload)
-- end

function Kitty:send(text, on_exit, stdio)
  return self:api_command("send-text", { "--", text }, on_exit, stdio)
end
function Kitty:send_file(from_file, on_exit, stdio)
  return self:api_command("send-text", {
    "--from-file",
    (from_file or vim.api.nvim_buf_get_name(0)),
  }, on_exit, stdio)
end

local termcodes = vim.api.nvim_replace_termcodes
local function t(k)
  return termcodes(k, true, true, true)
end
function Kitty:send_key(text)
  print(text)
  vim.notify("Unimplemented", vim.log.levels.ERROR, {})
end

-- https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitty-get-text-extent
function Kitty:get_text(extent, with_text, on_exit)
  local stdout = vim.loop.new_pipe(false)
  self:api_command("get-text", { "--extent", (extent or "screen") }, on_exit)

  vim.loop.read_start(stdout, function(err, data)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    if data then
      with_text(data)
    end
  end)
end

function Kitty:scroll(opts, on_exit, stdio)
  local amount = opts.amount
  if not amount and opts.till_end then
    amount = "end"
  end
  if not amount and opts.till_start then
    amount = "start"
  end
  if not amount and opts.up then
    amount = tostring(opts.up) .. "-"
  end
  if not amount and opts.down then
    amount = tostring(opts.down) .. "+"
  end
  return self:api_command("scroll", {
    amount,
  }, on_exit, stdio)
end
function Kitty:scroll_up(opts, on_exit, stdio)
  return self:scroll(vim.list_extend(opts or {}, { up = 1 }), on_exit, stdio)
end
function Kitty:scroll_down(opts, on_exit, stdio)
  return self:scroll(vim.list_extend(opts or {}, { down = 1 }), on_exit, stdio)
end
Kitty.signal_child = from_api_command "signal-child"
function Kitty:ls(cb, on_exit, stdio)
  local stdout
  if stdio == nil or stdio[2] == nil then
    stdout = vim.loop.new_pipe(false)
    stdio = { nil, stdout, nil }
  else
    stdout = stdio[2]
  end

  local handle, pid = self:api_command("ls", {}, on_exit, stdio)
  vim.loop.read_start(stdout, function(err, data)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    if data then
      if cb then
        cb(vim.json.decode(data)) -- TODO: parse json
      end
    end
  end)
end
Kitty.font_size = from_api_command "set-font-size"
Kitty.set_spacing = from_api_command "set-spacing"

function Kitty:set_match_arg(opts)
  if type(opts) == "string" then
    self.match_arg = opts
    return
  end
  for k, v in pairs(opts) do
    self.match_arg = k .. ":" .. tostring(v)
  end
end
function Kitty:set_match_arg_from_id(id)
  self:set_match_arg { id = id }
end
function Kitty:set_match_arg_from_pid(pid)
  -- FIXME: I dont think pid match_arg works
  self:set_match_arg { pid = pid }
end
function Kitty:universal()
  return self:new { match_arg = "" }
end
function Kitty:recent(i)
  return self:new { match_arg = "recent:" .. (i or 0) }
end
function Kitty:current_tab()
  return self:new { is_tab = self.is_tab }
end

function Kitty:new(o)
  o = o or {}
  setmetatable(o, self)
  self.__index = self

  -- Setup stuff
  if o.listen_on == "unique_port" then
    o.listen_on = Kitty.port_from_pid()
  end
  if o.attach_to_current_win then
    o.listen_on = Kitty.current_win_listen_on()
    o.from_id = Kitty.current_win_id()
    o.is_opened = true
    o.open = function(...) end
    o.attach_to_current_win = nil
  end
  if o.from_id then
    o:set_match_arg_from_id(o.from_id)
    o.from_id = nil
  end
  -- Warn about Duplicate window titles
  for _, v in ipairs(titles) do
    if o.title == v then
      vim.notify("Kitty Window title already used: " .. o.title, vim.log.WARN, {})
    end
  end
  titles[#titles + 1] = o.title

  return o
end

Kitty.setup_make = require("kitty.make").setup
Kitty.setup_repl = require("kitty.repl").setup

return Kitty
