local M = {}
local function nop(...) return ... end

function M.call_or_input(self, arg, fun, input_opts, from_input, ...)
  if type(fun) == "string" then fun = self[fun] end

  if arg == nil then
    local opts = input_opts
    if type(input_opts) == "function" then opts = input_opts(self) end

    from_input = from_input or nop
    local extra_args = { ... };
    (self.input or vim.ui.input)(opts, function(i) fun(self, from_input(i), unpack(extra_args)) end)
  else
    fun(self, arg, ...)
  end
end
function M.call_or_select(self, arg, fun, choices, from_input, ...)
  if type(fun) == "string" then fun = self[fun] end

  if arg == nil then
    local opts = choices
    if type(choices) == "function" then opts = choices(self) end

    local extra_args = { ... };
    (self.select or vim.ui.select)(opts[1], opts[2], function(i)
      from_input = from_input or nop
      fun(self, from_input(i), unpack(extra_args))
    end)
  else
    fun(self, arg, ...)
  end
end

-- TODO: complete this :(
local CSI = "\x1b["
local SFT = ";2"
local CTL = ";5"
local unkeycode_map = {
  ["<cr>"] = "\r",
  -- ["<cr>"] = CSI .. "13u",
  ["<S-cr>"] = CSI .. "13" .. SFT .. "u",
  ["<c-cr>"] = CSI .. "13" .. CTL .. "u",
  CSI = CSI,
}
M.unkeycode_map = unkeycode_map
function M.unkeycode(c) return unkeycode_map[c:lower()] or c end

function M.current_term_listen_on() return vim.env.KITTY_LISTEN_ON end
function M.current_win_id() return vim.env.KITTY_WINDOW_ID end
local unique_listen_on_counter = 0
function M.port_from_pid(prefix)
  unique_listen_on_counter = unique_listen_on_counter + 1
  return (prefix or "unix:/tmp/kitty.nvim-") .. vim.fn.getpid() .. unique_listen_on_counter
end

M.api_commands_no_match = {
  ["set-font-size"] = true,
  ["ls"] = true,
}
function M.match_expr_from_tbl(tbl, conv_keys)
  local m = nil
  for k, v in pairs(tbl) do
    local e = (conv_keys and conv_keys(k) or k) .. ":" .. tostring(v)
    m = m and (m .. " and " .. e) or e
  end
  return m
end
---Append arguments required to match some kitty window
---@param args string[] output parameter
---@param match_arg {[string]:string} table of match queries (see Kitty docs)
---@param use_window_id boolean|string should specifically match only the window,
---                                    pass a string to figure it out automatically from the command
---@param flag string? "--match" or something else
---@return string[] args
function M.append_match_args(args, match_arg, use_window_id, flag)
  if type(use_window_id) == "string" then
    use_window_id = use_window_id:sub(-4) == "-tab"
      or use_window_id:sub(-7) == "-layout"
      or use_window_id:sub(-8) == "-layouts"
  end
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
function M.build_api_command(listen_on, match_arg, kitty_exe, cmd, args)
  local built_args = { kitty_exe, "@", "--to", listen_on, cmd }
  if not M.api_commands_no_match[cmd] then M.append_match_args(built_args, match_arg, cmd) end
  built_args = vim.list_extend(built_args, args or {})
  -- vim.print(debug.traceback(vim.iter(built_args):join " "))
  return built_args
end
local system = vim.system
function M.api_command(listen_on, match_arg, kitty_exe, cmd, args, system_opts, on_exit)
  system_opts = system_opts or {}
  local cmdline = M.build_api_command(listen_on, match_arg, kitty_exe, cmd, args)
  return system(
    cmdline,
    vim.tbl_extend("keep", system_opts, {
      stderr = function(err, data)
        vim.schedule(function()
          if err then error(err) end
          if data then
            vim.print("From: " .. cmd .. " - " .. table.concat(args, " "), vim.log.levels.WARN)
            vim.print(data, vim.log.levels.ERROR)
          end
        end)
      end,
      text = true,
    }),
    on_exit
  )
end

function M.nvim_env_injections(opts)
  if opts.inject_nvim_env then
    return {
      NVIM_LISTEN_ADDRESS = vim.v.servername,
      NVIM = vim.v.servername,
      NVIM_PID = vim.fn.getpid(),
    }
  else
    return {
      NVIM_LISTEN_ADDRESS = false,
      NVIM = false,
      NVIM_PID = false,
    }
  end
end
function M.env_injections(env, args)
  if env then
    for k, v in pairs(env) do
      args[#args + 1] = "--env"
      if v == false then
        args[#args + 1] = k -- remove
      else
        args[#args + 1] = k .. "=" .. v
      end
    end
  end
end

-- TODO: use vim.fn.getregion
function M.get_selection(type)
  local feedkeys = vim.api.nvim_feedkeys
  local t = vim.keycode
  local bufnr = vim.api.nvim_get_current_buf()
  local start_mark, finish_mark = "[", "]"
  if type == "v" or type == "V" or type == t "<C-v>" then
    start_mark, finish_mark = "<", ">"
    -- vim.cmd([[execute "normal! \<esc>"]])
    feedkeys(t "<esc>", "nix", false)
  end

  local start = vim.api.nvim_buf_get_mark(bufnr, start_mark)
  local finish = vim.api.nvim_buf_get_mark(bufnr, finish_mark)

  if type == "line" or type == "V" then
    return vim.api.nvim_buf_get_lines(bufnr, start[1] - 1, finish[1], false)
  elseif type == "block" or type == t "<C-v>" then
    local lines = vim.api.nvim_buf_get_lines(bufnr, start[1] - 1, finish[1], false)
    return vim.tbl_map(function(l) return l:sub(start[2], finish[2]) end, lines)
  else
    return vim.api.nvim_buf_get_text(0, start[1] - 1, start[2], finish[1] - 1, finish[2] + 1, {})
  end
end

function M.kitten_exe()
  if vim.fn.executable "kitten" == 1 then return "kitten" end
  return "kitty"
end

function M.staticify(inst, K)
  return setmetatable(K or {}, {
    __index = function(m, k)
      local ret = inst[k]
      if type(ret) == "function" then
        local f = function(...) return ret(inst, ...) end
        m[k] = f
        return f
      else
        return ret
      end
    end,
  })
end

function M.dump_to_buffer(bufnr, data, cb)
  if type(bufnr) == "function" then bufnr = bufnr() end
  if bufnr == nil then
    vim.cmd.vsplit() -- TODO: customize, use nvim_open_win
    vim.cmd.enew()
    bufnr = vim.api.nvim_get_current_buf()
  elseif bufnr == "tab" then
    vim.cmd.tabnew()
    bufnr = vim.api.nvim_get_current_buf()
  end
  if cb then
    cb() -- nvim_buf_call
  end
  if type(data) == "function" then data = data() end
  if type(data) == "string" then data = vim.split(data, "\n") end
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, data)
  return bufnr, data
end

function M.in_sequence(f, list, on_exit)
  local dep_stdout
  local i = 1
  local function run_next(out)
    if out.code ~= 0 then return end
    if list[i] then
      dep_stdout[i] = out.stdout
      f(list[i], run_next)
    else
      on_exit(dep_stdout)
    end
  end
  run_next { code = 0 }
end

M.to_arg = setmetatable({}, {
  __call = function(t, k, v)
    local ret = "--" .. k:gsub("_", "-") .. "=" .. v
    return ret
  end,
  __index = function(t, k)
    local ret = "--" .. k:gsub("_", "-")
    return ret
  end,
})

return M
