-- WOW all this boilerplate is so worth it and totally works
local M = {}
local function match(lead, args)
  return vim
    .iter(args)
    :filter(function(arg)
      -- If the user has typed `:Rocks install ne`,
      -- this will match 'neorg'
      return arg:find(lead) ~= nil
    end)
    :totable()
end
M.match = match
M.matcher = function(args)
  return function(lead) return match(lead, args) end
end

---@class KittySubcommand
---@field impl fun(args:string[], opts: table) The command implementation
---@field complete? fun(subcmd_arg_lead: string): string[] (optional) Command completions callback, taking the lead of the subcommand's arguments

function M.register(name, opts)
  local subcommand_tbl = opts.subcommands
  vim.api.nvim_create_user_command(name, function(args)
    local fargs = args.fargs
    local subcommand_key = fargs[1]
    local subcommand = subcommand_tbl[subcommand_key]
    if not subcommand then
      vim.notify(name .. ": Unknown command: " .. subcommand_key, vim.log.levels.ERROR)
      return
    end
    -- Invoke the subcommand
    -- Get the subcommand's arguments, if any
    subcommand.impl(#fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}, args)
  end, {
    nargs = "+",
    desc = opts.desc or name,
    complete = function(arg_lead, cmdline, _)
      -- Get the subcommand.
      local subcmd_key, subcmd_arg_lead = cmdline:match "^Rocks[!]*%s(%S+)%s(.*)$"
      if subcmd_key and subcmd_arg_lead and subcommand_tbl[subcmd_key] and subcommand_tbl[subcmd_key].complete then
        -- The subcommand has completions. Return them.
        return subcommand_tbl[subcmd_key].complete(subcmd_arg_lead)
      end
      -- Check if cmdline is a subcommand
      if cmdline:match "^" .. name .. "[!]*%s+%w*$" then
        -- Filter subcommands that match
        local subcommand_keys = vim.tbl_keys(subcommand_tbl)
        return vim.iter(subcommand_keys):filter(function(key) return key:find(arg_lead) ~= nil end):totable()
      end
    end,
    bang = true,
  })
end

return M
