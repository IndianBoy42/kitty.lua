local Make = {}

local function nop(...)
  return ...
end

--- Helper to find a build file
function Make.find_build_file(pattern, args)
  vim.notify("TODO: search cwd/lsp_root_dir for " .. pattern, vim.log.levels.WARN)
end

function Make.from_command(cmd, args, parse)
  local loop = vim.loop
  local stdout = loop.new_pipe(false)
  loop.spawn(cmd, { args = args, stdio = { nil, stdout, nil } }, function()
    if stdout then
      stdout:read_stop()
      stdout:close()
    end
  end)
  loop.read_start(stdout, function(err, data)
    if err then
      vim.notify("Error running command: " .. err, vim.log.levels.ERROR)
      return
    end

    if data then
      parse(data)
    end
  end)
end

-- Append commands to self.targets
-- name = { cmd = '', desc = ''}
Make.builtin_target_providers = require "kitty.make.builtins"

function Make.setup(T)
  -- Options, state variables, etc
  T.cmd_history = {}
  T.targets = {
    default = { desc = "Default" },
    last_manual = { desc = "Last Run Command" },
    last = { desc = "Last Run Task" },
    -- on_save = { desc = "Will Run on Save" }, -- TODO: auto_on_save commands
    -- TODO: combo tasks
  }
  T.focus_me = T.focus_me or false
  T.select = T.select or vim.ui.select
  T.input = T.input or vim.ui.input
  T.shell = T.shell or vim.o.shell
  T.default_run_opts = T.default_run_opts or {}
  T.task_choose_format = T.task_choose_format
    or function(i, _)
      local name, target = unpack(i)
      local desc = name .. ": " .. target.desc
      if target.cmd == nil or target.cmd == "" then
        desc = desc .. " (no command)"
      end
      return desc
    end

  -- Functions
  function T:target_list(filter)
    local list = self.target_list_cache
    if list and not filter then
      return list
    end

    if not list then
      -- TODO: this is kinda inefficient... luajit go brrrrr
      list = {}
      for k, v in pairs(self.targets) do
        list[#list + 1] = { k, v }
      end
      table.sort(list, function(a, b)
        if a[1] == "default" then
          return true
        elseif b[1] == "default" then
          return false
        end

        if a[2].priority or b[2].priority then
          return (a[2].priority or 0) >= (b[2].priority or 0)
        end

        return a[1] < b[1]
      end)
      self.target_list_cache = list
    end

    if filter then
      list = vim.tbl_filter(filter, list)
    end

    return list
  end
  function T:call_or_input(arg, fun, input_opts, from_input)
    if type(fun) == "string" then
      fun = self[fun]
    end

    if arg == nil then
      local opts = input_opts
      if type(input_opts) == "function" then
        opts = input_opts(self)
      end

      from_input = from_input or nop
      self.input(opts, function(i)
        fun(self, from_input(i))
      end)
    else
      fun(self, arg)
    end
  end
  function T:call_or_select(arg, fun, choices, from_input)
    if type(fun) == "string" then
      fun = self[fun]
    end

    if arg == nil then
      local opts = choices
      if type(choices) == "function" then
        opts = choices(self)
      end

      self.select(opts[1], opts[2], function(i)
        from_input = from_input or nop
        fun(self, from_input(i))
      end)
    else
      fun(self, arg)
    end
  end
  function T:_add_target_provider(provider)
    local f = type(provider) == "function" and provider or Make.builtin_target_providers[provider]
    f(self.targets, self)
  end
  function T:add_target_provider(provider, force)
    local providers = vim.tbl_keys(Make.builtin_target_providers)
    -- TODO: filter by really available providers?
    if force then
      print "unimplemented"
    end
    self:call_or_select(provider, "_add_target_provider", { providers, { prompt = "Add from Builtin Providers" } })
  end
  function T:last_cmd()
    return self.cmd_history[#self.cmd_history]
  end
  function T:_run(cmd, opts)
    opts = opts or self.default_run_opts

    if type(cmd) == "function" then
      cmd = cmd(self)
    end

    if opts.focus_win then
    end

    cmd = cmd .. "\r"
    if opts.launch_new then
      return self:launch({}, opts.launch_new, { self.shell, "-c", cmd })
    else
      self:send(cmd)
    end
    -- TODO: can notify on finish?
  end
  function T:run_cmd(cmd, input_opts, run_opts, remember_cmd)
    self:call_or_input(
      cmd,
      "_run",
      vim.tbl_extend("force", {
        prompt = "Run in " .. self.title,
        default = self:last_cmd(),
      }, input_opts or {}),
      function(i)
        if remember_cmd then
          remember_cmd(i)
        end
        return i, run_opts
      end
    )
  end
  function T:run(cmd, input_opts, run_opts, remember_cmd)
    self:run_cmd(cmd, input_opts, run_opts, function(i)
      if remember_cmd then
        remember_cmd(i)
      end
      self.cmd_history[#self.cmd_history + 1] = cmd
      self.targets.last_manual.cmd = cmd
    end)
  end
  function T:rerun(run_opts)
    self:run_cmd(self:last_cmd(), nil, run_opts)
  end
  function T:kill_ongoing()
    -- 0x03 is ^C
    self:send "\x03"
  end
  function T:_choose_default(target_name)
    self.targets.default = self.targets[target_name]
    if self.target_list_cache then
      self.target_list_cache[1] = self.targets.default
    end
  end
  function T:choose_default(target_name)
    self:call_or_select(target_name, "_choose_default", {
      self:target_list(),

      {
        prompt = "Choose default for " .. self.title,
        format_item = self.task_choose_format,
      },
    })
  end
  function T:_make(target, run_opts)
    if type(target) == "string" then
      target = self.targets[target]
    end
    local cmd = target.cmd or target[2].cmd
    self.targets.last.cmd = cmd
    self:run_cmd(cmd, {
      prompt = "Chosen Task has no Cmd",
    }, run_opts or target.run_opts, run_opts)
  end
  function T:make(target, run_opts, filter)
    self:call_or_select(target, "_make", {
      self:target_list(filter),
      {
        prompt = "Run target in " .. self.title,
        format_item = self.task_choose_format,
      },
    }, function(i)
      return (i or "default"), run_opts
    end)
  end
  function T:make_default(run_opts)
    self:make("default", run_opts)
  end
  function T:make_last(run_opts)
    self:make("last", run_opts)
  end
  function T:_add_target(name, target, run_opts)
    self.targets[name] = type(target) == "table" and target
      or {
        cmd = target,
        desc = name,
        run_opts = run_opts,
      }
    self.target_list_cache = nil
  end
  function T:add_target(name, target, run_opts)
    function self:_add_target2(target_)
      self:call_or_input(name, "_add_target", {
        prompt = "Name: ",
        default = "default",
      }, function(name_)
        return name_, target_, run_opts
      end)
    end
    self:call_or_input(target, "_add_target", {
      prompt = "Cmd: ",
    })
    -- self.targets[name] = type(target) == "table" and target or { cmd = target, desc = name }
  end
  function T:_target_from_last_run(name)
    self.targets[name] = {
      name = name,
      desc = name,
      cmd = self.targets.last_manual.cmd,
    }
    self.target_list_cache = nil
  end
  function T:target_from_last_manual(name, run_opts)
    self:call_or_input(name, "_add_target", { prompt = "Name" }, function(i)
      return i, vim.deepcopy(self.targets.last_manual), run_opts
    end)
  end

  function T:rust_tools_executor(opts)
    opts = opts or T.default_run_opts
    return {
      execute_command = function(command, args, cwd)
        self:_run("cd " .. cwd .. " && " .. command .. " " .. table.concat(args, " "), opts)
      end,
    }
  end

  -- TODO: dynamic target providers (eg. RustRunnables)
  if T.target_providers ~= nil then
    if type(T.target_providers) ~= "table" then
      T.target_providers = { T.target_providers }
    end
    for _, v in ipairs(T.target_providers) do
      T:_add_target_provider(v)
    end
  end
end

return Make
