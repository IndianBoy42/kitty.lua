return {
  ["make"] = function(targets, _)
    targets.make = {
      cmd = "make",
      desc = "Run Makefile",
      priority = 100,
    }
    targets.default = targets.make
  end,
  ["just"] = function(targets, _)
    if not vim.fn.executable "just" then
      return
    end

    targets["just: <default>"] = {
      cmd = "just",
      desc = "Run just with no args",
      priority = 100,
    }

    require("kitty.make").from_command("just", { "--list" }, function(data)
      local lines = vim.split(data, "\n")
      for i, line in ipairs(lines) do
        if i > 1 then -- Skip first line
          local parts = vim.split(line, "#")
          local name = vim.trim(parts[1])
          if name ~= "" then
            local desc = parts[2] and vim.trim(parts[2]) or name
            targets["just: " .. name] = { cmd = "just " .. name, desc = desc }
          end
        end
      end
    end)

    targets.default = targets.just_default
  end,
  ["cargo"] = function(targets)
    if not vim.fn.filereadable "Cargo.toml" or not vim.fn.executable "cargo" then
      return
    end

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

    -- Make.from_command("cargo", {"--", "--list"}, parse)

    targets.default = targets.check
  end,
}
