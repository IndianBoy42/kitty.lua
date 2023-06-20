local M = {}
local function nop(...)
  return ...
end

function M.call_or_input(self, arg, fun, input_opts, from_input, ...)
  if type(fun) == "string" then
    fun = self[fun]
  end

  if arg == nil then
    local opts = input_opts
    if type(input_opts) == "function" then
      opts = input_opts(self)
    end

    from_input = from_input or nop
    local extra_args = { ... };
    (self.input or vim.ui.input)(opts, function(i)
      fun(self, from_input(i), unpack(extra_args))
    end)
  else
    fun(self, arg, ...)
  end
end
function M.call_or_select(self, arg, fun, choices, from_input, ...)
  if type(fun) == "string" then
    fun = self[fun]
  end

  if arg == nil then
    local opts = choices
    if type(choices) == "function" then
      opts = choices(self)
    end

    local extra_args = { ... };
    (self.select or vim.ui.select)(opts[1], opts[2], function(i)
      from_input = from_input or nop
      fun(self, from_input(i), unpack(extra_args))
    end)
  else
    fun(self, arg, ...)
  end
end

function M.unkeycode(c) end

function M.current_win_listen_on()
  return vim.env.KITTY_LISTEN_ON
end
function M.current_win_id()
  return vim.env.KITTY_WINDOW_ID
end
local unique_listen_on_counter = 0
function M.port_from_pid(prefix)
  unique_listen_on_counter = unique_listen_on_counter + 1
  return (prefix or "unix:/tmp/kitty.nvim-") .. vim.fn.getpid() .. unique_listen_on_counter
end

M.api_commands_no_match = {
  "set-font-size",
  "ls",
}
function M.match_expr_from_tbl(tbl, conv_keys)
  local m = nil
  for k, v in pairs(tbl) do
    local e = (conv_keys and conv_keys(k) or k) .. ":" .. tostring(v)
    m = m and (m .. " and " .. e) or e
  end
  return m
end
function M.append_match_args(args, match_arg, use_window_id, flag)
  if match_arg and match_arg ~= "" then
    vim.list_extend(args, {
      flag and flag or "--match",
      M.match_expr_from_tbl(match_arg, use_window_id and function(k)
        if k == "id" then
          return "window_id"
        elseif k == "title" then
          return "window_title"
        else
          return k
        end
      end),
    })
  end
  return args
end
function M.build_api_command(listen_on, match_arg, cmd, args_)
  local args = { "@", "--to", listen_on, cmd }
  if not vim.tbl_contains(M.api_commands_no_match, cmd) then
    M.append_match_args(args, match_arg, cmd:sub(-4) == "-tab" or cmd:sub(-7) == "-layout" or cmd:sub(-8) == "-layouts")
  end
  args = vim.list_extend(args, args_ or {})
  return args
end
function M.api_command(listen_on, match_arg, cmd, args_, on_exit, stdio)
  local spawn_args = M.build_api_command(listen_on, match_arg, cmd, args_)
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
      vim.notify("M. " .. data, vim.log.levels.ERROR)
      vim.notify("From: " .. cmd .. " - " .. table.concat(spawn_args, " "), vim.log.levels.WARN)
    end
  end)

  return handle, pid
end
function M.api_command_blocking(listen_on, match_arg, cmd, args_)
  local cmdline = M.build_api_command(listen_on, match_arg, cmd, args_)
  cmdline = { "kitty", unpack(cmdline) }
  vim.fn.system(cmdline)
end

function M.nvim_env_injections()
  return {
    NVIM_LISTEN_ADDRESS = vim.v.servername,
    NVIM = vim.v.servername,
    NVIM_PID = vim.fn.getpid(),
  }
end

return M
