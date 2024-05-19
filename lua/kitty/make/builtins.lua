local kutils = require("kitty.utils")
local function from_cmd(...) return require("kitty.make").from_command(...) end
local function justfile(targets, fname)
  if vim.fn.executable "just" == 0 then return end
  if fname then
    fname = "--justfile=" .. fname
  else
    fname = " "
  end

  targets["just: <default>"] = { -- TODO: fill in the name from just --list
    cmd = "just" .. fname,
    desc = "Run just with no args",
    priority = 999,
    provider = "just",
  }

  from_cmd({ "just", "--list", fname }, function(data)
    local lines = vim.split(data, "\n")
    for i, line in ipairs(lines) do
      if i > 1 then -- Skip first line
        local parts = vim.split(line, "#")
        local name = vim.trim(parts[1])
        if name ~= "" then
          local desc = parts[2] and vim.trim(parts[2]) or name
          targets["just: " .. name] = {
            cmd = "just " .. name,
            desc = desc,
            provider = "just",
            priority = #lines + 2 - i,
          }
        end
      end
    end
  end)

  targets.default = targets.just_default
end

---@class KittyTarget
---@field cmd string
---@field desc string
---@field priority number?
---@field after table -- TODO: more specific
---@field depends table -- TODO: more specific

return {
  ["make"] = function(targets)
    targets["make: <default>"] = {
      cmd = "make",
      desc = "Run make with no args ",
      priority = 999,
    }
    targets.default = targets.make
  end,
  ["just"] = function(targets) justfile(targets) end,
  ["thisjustfile"] = function(targets)
    local fname = vim.api.nvim_buf_get_name(0)
    justfile(targets, fname)
  end,
  ["cargo"] = function(targets)
    -- TODO: this could be more configurable, more post-task stuff
    if vim.fn.filereadable "Cargo.toml" == 0 or vim.fn.executable "cargo" == 0 then return end

    targets.check = {
      cmd = "cargo check",
      desc = "Check Cargo Project",
      priority = 100,
    }
    targets.build = {
      cmd = "cargo build",
      desc = "Build Cargo Project",
      priority = 99,
    }
    targets.test = {
      cmd = "cargo test",
      desc = "Test Cargo Project",
      priority = 98,
      -- TODO: we can add a post task that parses the list of targets?
    }
    targets.run = {
      cmd = "cargo run",
      desc = "Run Cargo Project",
      priority = 97,
    }
    targets.bench = {
      cmd = "cargo bench",
      desc = "Run Cargo Project",
      priority = 96,
    }
    targets.build_release = {
      cmd = "cargo build --release",
      desc = "Build Cargo Project --release",
      priority = 95,
    }
    targets.test_release = {
      cmd = "cargo test --release",
      desc = "Test Cargo Project --release",
      priority = 94,
    }
    targets.run_release = {
      cmd = "cargo run --release",
      desc = "Run Cargo Project --release",
      priority = 93,
    }
    targets.update = {
      cmd = "cargo update",
      desc = "Update Cargo Dependencies",
      priority = 50,
    }
    targets.publish = {
      cmd = "cargo publish",
      desc = "Publish Cargo Project",
      priority = 50,
    }
    targets.tree = {
      cmd = "cargo tree",
      desc = "Show Cargo Tree",
      priority = 50,
      after = {
        lua = function(stdout)
          kutils.dump_to_buffer(nil, stdout)
        end
      }
    }
    targets.fix = {
      cmd = "cargo fix",
      desc = "Run Cargo Fix",
      priority = 50,
    }
    targets.install = {
      cmd = "cargo install --path .",
      desc = "Install Cargo Project",
      priority = 50,
    }
    targets.doc = {
      cmd = "cargo doc",
      desc = "Build Cargo Documentation",
      priority = 50,
    }

    local default_targets = vim.tbl_keys(targets)

    from_cmd({ "cargo", "--read-manifest" }, function(data)
      -- data is in json
      local manifest = vim.json.decode(data, {})
      for _, target in ipairs(manifest.targets) do
        targets["check " .. target.name] = {
          cmd = "cargo check " .. target.name,
          desc = "Check Cargo [" .. target.name .. "]",
          priority = 90,
        }
        targets["build " .. target.name] = {
          cmd = "cargo build " .. target.name,
          desc = "Build Cargo [" .. target.name .. "]",
          priority = 89,
        }
        targets["test " .. target.name] = {
          cmd = "cargo test " .. target.name,
          desc = "Test Cargo [" .. target.name .. "]",
          priority = 88,
        }
        targets["run " .. target.name] = {
          cmd = "cargo run " .. target.name,
          desc = "Run Cargo [" .. target.name .. "]",
          priority = 87,
        }
        targets["build " .. target.name .. " --release"] = {
          cmd = "cargo build --release " .. target.name,
          desc = "Build Cargo [" .. target.name .. "] --release",
          priority = 86,
        }
        targets["test " .. target.name .. " --release"] = {
          cmd = "cargo test --release " .. target.name,
          desc = "Test Cargo [" .. target.name .. "] --release",
          priority = 85,
        }
        targets["run " .. target.name .. " --release"] = {
          cmd = "cargo run --release " .. target.name,
          desc = "Run Cargo [" .. target.name .. "] --release",
          priority = 84,
        }
      end
    end)

    -- TODO: any way to get a list of tests
    from_cmd("cargo test -- -Zunstable-options --format json --list", function(data)
      local lines = vim.split(data, "\n")
      local names = {}
      for _, line in ipairs(lines) do
        line = vim.json.decode(line, {})
        if line.type == "test" then
          names[#names + 1] = line.name
          targets["test: " .. line.name] = {
            cmd = "cargo test " .. line.name,
            desc = "Test Cargo [" .. line.name .. "]",
            priority = 80,
          }
        end
      end
      local tests = {}
      for _, name in pairs(names) do
        local path = vim.split(name, "::")
        local last = tests
        for _, part in ipairs(path) do
          last[part] = last[part] or {}
          last = last[part]
        end
        last[path[#path]] = true
      end
      local function add_targets(t)
        for name, sub in pairs(t) do
          targets["test: " .. name] = {
            cmd = "cargo test " .. name,
            desc = "Test Cargo [" .. name .. "]",
            priority = 70,
          }
          if sub ~= true then
            add_targets(sub)
          end
        end
      end
      add_targets(tests)
    end)

    -- All the rest of the cargo subcommands
    from_cmd({ "cargo", "--list" }, function(data)
      local lines = vim.split(data, "\n")
      for i, line in ipairs(lines) do
        if i > 1 then -- Skip first line
          local name, desc = unpack(vim.split(line, "%s"))
          if vim.startswith(desc, "alias:") and
              #vim.split(desc, " ", {}) == 2 -- simple alias for a command with no arguments
          then
            goto continue
          end
          -- FIXME: inefficient only a few known
          if vim.tbl_contains(default_targets, name, {}) then goto continue end

          targets[name] = {
            cmd = name,
            desc = desc,
            priority = 0,
          }

          ::continue::
        end
      end
    end)

    -- TODO: cargo xtask

    targets.default = targets.check
  end,
  ["vscode"] = function(targets)
    if vim.fn.filereadable "tasks.json" == 0 and vim.fn.filereadable "launch.json" == 0 then return end
    -- TODO: https://code.visualstudio.com/docs/editor/tasks
    local tasks = vim.json.decode(io.open("tasks.json", "r"):read "*a").tasks
    local launch = vim.json.decode(io.open("launch.json", "r"):read "*a").configurations
  end,
}
