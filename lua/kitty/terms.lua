local M = {}
-- TODO: save this information to sessions?
local terms = {}
local kutils = require "kitty.utils"
M.terminals = terms

local function get_terminal(key)
  -- TODO: check if it is still open?
  if key == nil then return terms.global end
  if key == 0 then key = vim.api.nvim_get_current_win() end
  if terms[key] then return terms[key] end
  if type(key) == "number" then return terms.global end
end
M.get_terminal = get_terminal

local function get_terminal_name(args)
  local k = 0
  if args and args.fargs and #args.fargs > 0 then
    if args.fargs[1]:sub(1, 1) == ":" then
      k = args.fargs[1]:sub(2)

      for i = 1, #args.fargs do
        args.fargs[i] = args.fargs[i + 1]
      end
      args.args = table.concat(args.fargs, " ")
    end
  end
  if k == 0 then k = vim.api.nvim_get_current_win() end
  return k
end

local uuid = 0
local function get_uuid()
  uuid = uuid + 1
  return "_" .. uuid
end

local function new_terminal(where, opts, args, name)
  opts = opts or {}
  local cmd
  if args and args.fargs then
    cmd = args.fargs
  elseif type(args) == "string" then
    cmd = args
  else
    cmd = args
  end
  name = name
    or (type(cmd) == "string" and cmd)
    or (type(cmd) == "table" and type(cmd[1]) == "string" and cmd[1])
    or get_terminal_name(args)

  if not cmd or #cmd == 0 then
    -- TODO: something
  end

  opts.env_injections = opts.env_injections or {}
  -- TODO: use `kitty @ set-user-vars`
  if type(name) == "string" then
    opts.env_injections.KITTY_NVIM_NAME = name
  elseif type(name) == "number" then
    opts.env_injections.KITTY_NVIM_NAME = "buf_" .. name
  end

  if where == nil then where = true end
  terms[name] = require("kitty.current_win").launch(opts, where, cmd)
  terms[get_uuid()] = terms[name]
  if terms.global == nil then terms.global = terms[name] end
  return terms[name]
end
M.new_terminal = new_terminal
M.new_tab = function(opts, args, name) return new_terminal("tab", opts, args, name) end
M.new_window = function(opts, args, name) return new_terminal("window", opts, args, name) end
M.new_os_window = function(opts, args, name) return new_terminal("os-window", opts, args, name) end

local reuse_lib = {
  focus = function(where, opts, args, name, term)
    term:focus()
    -- TODO: if this fails then we launch a new terminal
    if false then return false end
    return true
  end,
}
reuse_lib.default = reuse_lib.focus
local where_map = { ["os-window"] = "new-window", ["tab"] = "new-tab", ["window"] = "this-tab" }
local function terminal(where, opts, args, name, reuse)
  local t = get_terminal(name)
  if t ~= nil then
    local function __reuse(out)
      vim.print(out)
      -- TODO: more specific on code?
      if out.code == 0 then
        if type(reuse) == "function" then
          reuse(where, opts, args, name, t)
        elseif type(reuse) == "string" then
          reuse_lib[reuse](where, opts, args, name, t)
        elseif reuse == nil then
          reuse_lib.default(where, opts, args, name, t)
        end
        return t
      else
        -- TODO: try this out
        if true then
          t:reopen(args):wait()
          return t
        end
        return new_terminal(where, opts, args, name)
      end
    end
    if t.launch_where ~= where then
      t = __reuse(t:move(where_map[where] or where, {}):wait()) -- blocking is just easier here
    else
      t = __reuse(t:ls_match(true, function() end):wait()) -- blocking is just easier here
    end
  else
    t = new_terminal(where, opts, args, name)
  end
  return t
end
M.use_terminal = terminal
M.use_tab = function(opts, args, name) return terminal("tab", opts, args, name) end
M.use_window = function(opts, args, name) return terminal("window", opts, args, name) end
M.use_os_window = function(opts, args, name) return terminal("os-window", opts, args, name) end
-- TODO: reuse based on foreground_process or other 

local attach_opts = {}
function M.kitty_attach(opts)
  opts = opts or attach_opts
  require("kitty").setup(opts, function(K, ls)
    terms.global = K.instance

    -- TODO: keep polling to update the terms
    -- or detect failing commands automatically
    local Term = require "kitty.term"
    for id, t in pairs(ls:all_windows()) do
      terms["k" .. id] = Term:new(vim.tbl_deep_extend("keep", {
        attach_to_win = id,
      }, require("kitty.ls").term_config(t)))
      if t.env and t.env.KITTY_NVIM_NAME then terms[t.env.KITTY_NVIM_NAME] = terms["k" .. id] end
    end

    if opts.on_attach then opts.on_attach(M, K, ls) end
  end)

  return require("kitty").instance
end

M.defaults = {}

M.setup = function(opts)
  local cmd = vim.api.nvim_create_user_command
  opts = vim.tbl_deep_extend("keep", opts or {}, M.defaults)
  if not opts.dont_attach then
    M.kitty_attach(opts.attach)
  else
    attach_opts = opts.attach
  end

  cmd("KittyTab", function(args) M.new_tab({}, args) end, { nargs = "*" })
  cmd("KittyWindow", function(args) M.new_window({}, args) end, { nargs = "*" })
  cmd("KittyNew", function(args) M.new_os_window({}, args) end, { nargs = "*" })
  cmd("Kitty", function(args)
    local k = get_terminal_name(args)
    local t = get_terminal(k)
    if not terms.global and (args.args == nil or #args.args == 0) then return M.kitty_attach() end
    if t then
      if args.fargs and #args.fargs > 0 then
        t:cmd(args.args)
      else
        -- TODO:
        t:focus()
      end
    else
      new_terminal(true, {}, args, k)
    end
  end, { nargs = "*" })
  cmd("KittyClose", function(args)
    local k = get_terminal_name(args)
    local t = get_terminal(k)
    if t then
      pcall(function() t:close() end)
      terms[k] = nil
    end
  end, { nargs = "*" })
  cmd("KittyDetach", function(args)
    local k = get_terminal_name(args)
    local t = get_terminal(k)
    if t then pcall(function() t:detach(args.fargs and args.fargs[1]) end) end
  end, { nargs = "*" })
  cmd("KittyListTerm", function(args) vim.print(terms) end, {})

  -- TODO: detect when terminals close

  -- vim.keymap.set("n", "<leader>mK", KT.run, { desc = "Kitty Run" })
  -- vim.keymap.set("n", "", require("kitty").send_cell, { buffer = 0 })
end

-- TODO: More convenient terminal management
-- toggleterm style
-- move term from other tab to current tab and away

M = setmetatable(M, {
  __index = function(t, k)
    local term = get_terminal(0)
    if type(term[k]) == "function" then
      return function(...) return term[k](term, ...) end
    else
      return term[k]
    end
  end,
})

return M
