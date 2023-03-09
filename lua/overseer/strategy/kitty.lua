--  ╭──────────────────────────────────────────────────────────╮
--  │ TODO: Implement an overseer strategy                     │
--  ╰──────────────────────────────────────────────────────────╯

local KittyStrategy = {}

-- https://github.com/stevearc/overseer.nvim/blob/979f93c57885739f1141e37542bad808a29f7a9a/lua/overseer/strategy/toggleterm.lua
function KittyStrategy.new(opts) end

function KittyStrategy:reset() end

function KittyStrategy:get_bufnr() end

---@param task overseer.Task
function KittyStrategy:start(task)
  ---@class overseer.Task
  ---@field id number
  ---@field result? table
  ---@field metadata table
  ---@field default_component_params table
  ---@field status overseer.Status
  ---@field cmd string|string[]
  ---@field cwd string
  ---@field env? table<string, string>
  ---@field strategy_defn nil|string|table
  ---@field strategy? overseer.Strategy
  ---@field name string
  ---@field bufnr number|nil
  ---@field exit_code number|nil
  ---@field components overseer.Component[]
  ---@field _subscribers table<string, function[]>
end

function KittyStrategy:stop() end

function KittyStrategy:dispose()
  self:stop()
  util.soft_delete_buf(self.bufnr)
end

return KittyStrategy
