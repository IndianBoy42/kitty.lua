return {
  ["make"] = function(targets, _)
    targets["make: <default>"] = {
      cmd = "make",
      desc = "Run make with no args ",
      priority = 999,
    }
    targets.default = targets.make
  end,
  ["just"] = function(targets, _)
    if vim.fn.executable "just" == 0 then return end

    targets["just: <default>"] = {
      cmd = "just",
      desc = "Run just with no args",
      priority = 999,
      provider = "just",
    }

    require("kitty.make").from_command({ "just",  "--list"  }, function(data)
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
  end,
  ["cargo"] = function(targets)
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
    }
    targets.run = {
      cmd = "cargo run",
      desc = "Run Cargo Project",
      priority = 97,
    }
    targets.build_release = {
      cmd = "cargo build --release",
      desc = "Build Cargo Project (W/ Optimizations)",
      priority = 96,
    }
    targets.test_release = {
      cmd = "cargo test --release",
      desc = "Test Cargo Project (W/ Optimizations)",
      priority = 95,
    }
    targets.run_release = {
      cmd = "cargo run --release",
      desc = "Run Cargo Project (W/ Optimizations)",
      priority = 94,
    }

    -- TODO: any way to get a list of targets??

    targets.default = targets.check
  end,
  ["vscode"] = function(targets)
    if vim.fn.filereadable "tasks.json" == 0 and vim.fn.filereadable "launch.json" == 0 then return end
    -- TODO: https://code.visualstudio.com/docs/editor/tasks
    local tasks = vim.json.decode(io.open("tasks.json", "r"):read "*a").tasks
    local launch = vim.json.decode(io.open("launch.json", "r"):read "*a").configurations
  end,
}
