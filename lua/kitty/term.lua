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

local api_commands_no_match = {
  "set-font-size",
  "ls",
}

function Kitty:build_api_command(cmd, args_)
  local args = { "@", "--to", self.listen_on, cmd }
  if not vim.tbl_contains(api_commands_no_match, cmd) then
    self:append_match_args(args)
  end
  args = vim.list_extend(args, args_ or {})
  return args
end
function Kitty:api_command(cmd, args_, on_exit, stdio)
  local spawn_args = self:build_api_command(cmd, args_)
  stdio = stdio or { nil, nil, nil }
  if not stdio[3] then -- stderr
    stdio[3] = vim.loop.new_pipe(false)
  end
  local handle, pid = vim.loop.spawn("kitty", {
    args = spawn_args,
    stdio = stdio,
  }, function(code, signal)
    if stdio then
      local stdin, stdout, stderr = unpack(stdio)
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
    end

    if on_exit then
      on_exit(code, signal)
    end
  end)

  stdio[3]:read_start(function(err, data)
    if err then
      error(err)
    end
    if data then
      vim.notify("Kitty: " .. data, vim.log.levels.ERROR)
      vim.notify("From: " .. cmd .. " - " .. table.concat(spawn_args, " "), vim.log.levels.WARN)
    end
  end)

  return handle, pid
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
  vim.schedule(function()
    vim.api.nvim_create_autocmd(evt or "VimLeavePre", {
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
  return function(self, args, on_exit, stdio)
    if self.is_opened then
      self:focus()
      return
    end

    local handle, pid = fn(self, args, on_exit, stdio)
    -- TODO: get the window/tab id

    self.is_opened = true

    return handle, pid
  end
end

function Kitty:nvim_env_injections()
  return {
    NVIM_LISTEN_ADDRESS = vim.v.servername,
    NVIM = vim.v.servername,
    NVIM_PID = vim.fn.getpid(),
  }
end

Kitty.open = open_if_not_yet(function(self, args_, on_exit, stdio)
  -- self:ls(nil, function(code, _)
  --   if code == 0 then
  --     return
  --   end
  -- end)

  local args = {
    "--listen-on",
    self.listen_on,
    "--override",
    "allow_remote_control=yes",
  }
  local env = Kitty:nvim_env_injections()
  if env then
    for k, v in pairs(env) do
      args[#args + 1] = "--override"
      args[#args + 1] = "env=" .. k .. "=" .. v
    end
  end
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
  if self.open_layout then
    args[#args + 1] = "--override"
    args[#args + 1] = "enabled_layouts='" .. self.open_layout .. ",*'"
  end
  if args_ then
    vim.list_extend(args, args_)
  elseif self.launch_cmd then
    if type(self.launch_cmd) == "string" then
      self.launch_cmd = { self.launch_cmd }
    end
    vim.list_extend(args, self.launch_cmd)
  end

  -- TODO: use jobstart?
  local handle, pid = vim.loop.spawn("kitty", {
    args = args,
    stdio = stdio,
  }, function(code, signal)
    self.is_opened = false

    if code == 0 then
      if not self.dont_close_on_leave then
        self:close_on_leave()
      end
    end

    if on_exit then
      on_exit(code, signal)
    end
  end)

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
  o.listen_on = self.listen_on
  if o.title == nil or o.title == self.title then
    o.title = self.title .. "-" .. self.launch_counter
    self.launch_counter = self.launch_counter + 1
  end
  o.attach_to_current_win = false
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
    "--cwd",
    open_cwd,
  }
  local env = Sub:nvim_env_injections()
  if env then
    for k, v in pairs(env) do
      Sub.launch_args[#Sub.launch_args + 1] = "--env"
      Sub.launch_args[#Sub.launch_args + 1] = k .. "=" .. v
    end
  end
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
    if not args_ and sub.launch_cmd then
      args_ = { sub.launch_cmd }
    elseif type(args_) == "string" then
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

    stdout:read_start(function(err, data)
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
  if type(o) == "string" and args == nil then
    args = { o }
  end
  return self:launch(o, "tab", args)
end
function Kitty:new_window(o, args)
  if type(o) == "string" and args == nil then
    args = { o }
  end
  return self:launch(o, "window", args)
end
function Kitty:new_hsplit(o, args)
  self:goto_layout "splits"
  if type(o) == "string" and args == nil then
    args = { o }
  end
  if type(args) == "string" then
    args = { args }
  end
  args = vim.list_extend({ "--location=hsplit" }, args or {})
  return self:launch(o, "window", args)
end
function Kitty:new_vsplit(o, args)
  self:goto_layout "splits"
  if type(o) == "string" and args == nil then
    args = { o }
  end
  if type(args) == "string" then
    args = { args }
  end
  args = vim.list_extend({ "--location=vsplit" }, args or {})
  return self:launch(o, "window", args)
end
function Kitty:new_os_window(o, args)
  if type(o) == "string" and args == nil then
    args = { o }
  end
  return self:launch(o, "os-window", args)
end
function Kitty:new_overlay(o, args)
  if type(o) == "string" and args == nil then
    args = { o }
  end
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
function Kitty:get_text(extent, with_text, args, on_exit)
  if not with_text then
    with_text = function(data)
      vim.cmd.split()
      vim.cmd.enew()
      vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(data, "\n"))
    end
  end
  if not with_text then
    error "with_text is required"
    return
  end
  local stdout = vim.loop.new_pipe(false)
  self:api_command("get-text", vim.list_extend({ "--extent", (extent or "screen") }, args or {}), on_exit)

  stdout:read_start(function(err, data)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    if data then
      with_text(data)
    end
  end)
end
function Kitty:get_selection(reg)
  self:get_text("selection", function(data)
    vim.fn.setreg(reg, data)
  end, {})
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
  stdout:read_start(function(err, data)
    if err then
      vim.notify(err, vim.log.levels.ERROR)
    end
    if data then
      if cb then
        local decoded = vim.json.decode(data)
        cb(decoded)
      end
    end
  end)
  return handle, pid
end
Kitty.font_size = from_api_command "set-font-size"
Kitty.font_up = from_api_command("set-font-size", { "--", "+1" })
Kitty.font_down = from_api_command("set-font-size", { "--", "-1" })
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
