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

return M
