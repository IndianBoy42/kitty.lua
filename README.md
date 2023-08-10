# Kitty.lua - an API for remote controlling kitty terminals from neovim

## Features

- OOP based lua API for the Kitty remote control protocol to build other projects/plugins
- Integrations

## TODO

- Async-ify: Rewrite to `vim.system` + `lewis6991/async.nvim` for much cleaner API

- inject the correct nvim environment variables so neovim-remote works

- Integrate with [overseer.nvim](https://github.com/stevearc/overseer.nvim/blob/master/doc/strategies.md)

- Mirror the toggleterm API to be a drop in replacement

- Integrate with: neotest

- Implement the [protocol](https://sw.kovidgoyal.net/kitty/rc_protocol/) directly

- Make the attach and current_win work for cases like using neovide

- Needs real documentation

# USAGE

The bulk of the api is in `require'kitty.term'`,
and accessible through methods on a kitty terminal object.
In general, each terminal object you get represents one kitty window (not os window).

NOTE: pay close attention to whether the code snippets use `.` (function call) or `:` (method call)

There are a few way to get these objects, depending on what you want to do.

The most direct way is to call `require'kitty.term':new { }`
to get an object representing a new kitty terminal.
You probably want to assign it to a variable (call it `K`) and keep it around.
If you are not attaching to an existing terminal (by specifying `listen_on` and maybe `from_id`) then you should call `K:open()`.

If your usage is fairly simple you and not a plugin yourself, then you can use `require'kitty'.setup { }`.
This is roughly equivalent to `require'kitty.term':new {}`, however the terminal object api is now accessible through `require'kitty'.<api>`.
Note that that is a `.`(period) and not a `:`(colon), because the object is wrapped in a more normal lua api.
You can get the underlying object with `require'kitty'.instance`,
and use it like any other object from `require'kitty.term':new`,
In case another plugin requires the raw object.
This is a good globally available 'default' terminal.
By default this represents a new os-window.

You can get an object representing the current window that neovim is running in with `require'kitty.current_win'`.
Once again the object is wrapped so you don't have to use `:<api>()` and just use `.<api>()`.
This object again represents the kitty window, not the os window, that actually contains neovim,
so its not really useful for running commands, mostly for other rc commands.
You should use `sub_window` and the related api's `launch, new_window, new_tab, ...` to create a new kitty window and run things in that.

A shortcut for this pattern of creating a new kitty window inside the os window that contains neovim is:

```lua
require'kitty'.setup {
    from_current_win = "window" -- see require'kitty.enums' for the choices and
    -- https://sw.kovidgoyal.net/kitty/remote-control/#cmdoption-kitty-launch-type
    -- for the meaning
}
```

This makes `require'kitty'` represent a new kitty window in the current os window,
created where you tell it (a split, or a new tab, is the most common choice)

## Recipes

Install with lazy.nvim

```lua
  return {
    "IndianBoy42/kitty.lua",
    opts = { -- This is passed to require'kitty'.setup
        -- from_current_win =
    }
    config = function(_, opts)
        require'kitty'.setup(opts)

        -- Define commands and keymaps here
    end
    -- Define your lazy loading triggers
    cmd = {},
    keys = {
      {
        "<leader>ok",
        "<cmd>require'kitty'.open()<cr>",
        desc = "Kitty Open",
      },
    },
  }
```

All the examples will use `require'kitty'.<api>`, but they can all be replaced with `K:<api>` to work with any kitty terminal object/window

Create a command that launches a new tab running the command you ask for

```lua
vim.api.nvim_create_user_command("Kitty", function(args)
    if args.fargs and #args.fargs > 0 then
      -- Replace this with any other `new_*` api to choose where to launch it
      -- new_window, new_os_window, new_overlay, new_tab are all good
      -- You can also use 'kitty.current_win'
      require'kitty'.new_tab({
          keep_open = true, -- Keep the window open when the launched process exits,
          -- good(necessary) for short running commands
          focus_on_open = false, -- Dont change focus to the new window
      }, args.fargs)
    end
end, { nargs = "*" })
```

Use Kitty to execute `:RustRunnables` commands and codelens from `rust-tools.nvim`

```lua
require("rust-tools").config.options.tools.executor = require'kitty'.rust_tools_executor()
```

## kitty.term API

<https://sw.kovidgoyal.net/kitty/remote-control/#kitty>

TODO complete this

## kitty.make

A mini build runner, I hope someone can help me integrate Kitty.lua as a backend for other more feature complete build runners, but for now:

```lua
require'kitty'.setup_make() -- Make all the make functions available to the global instance
K:setup_make() -- Initialize make within some other kitty window
```

### `Kitty:run(cmd, run_opts, remember_cmd)`

Run the command `run` in the Kitty window.

`cmd` is optional, if not provided will call `vim.ui.input` to let you type a command

`run_opts` is optional, will use `Kitty.default_run_opts` if not given. All fields are optional

```lua
run_opts = {
    launch_new = "window" -- Run the command in a new window, takes the same `where` arguments as `Kitty:launch`
    focus_on_open = true -- if `focus_on_open` is true then change focus to the kitty window that runs the command (`focus_on_open` argument to `Kitty:launch`)
    keep_open = true -- if new window is launched for the process then controls whether it is kept open after the process completes (`keep_open` argument to `Kitty:launch`)
}
```

You can create a `!` like command around `Kitty:run`

```lua
vim.api.nvim_create_user_command("KittyRun", function(args)
    if args.args and #args.args > 0 then
      require'kitty'.run(args.args)
    end
end, { nargs = "*" })
```

### `Kitty:make(task, run_opts, filter)`

## kitty.repl

A mini repl sender
