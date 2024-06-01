local K = {}
local kutils = require "kitty.utils"
local defaults = {
  title = "Kitty-current-win",
  attach_to_win = true,
}
K.setup = function(cfg)
  cfg = vim.tbl_extend("keep", cfg or {}, defaults)

  local Term = require "kitty.term"
  local KT = Term:new(cfg)
  K.instance = KT

  -- Create the illusion of the global singleton, so can use . rather than :
  kutils.staticify(KT, K)

  -- TODO: mirror guifont? guifb, guibg
  local guifontsize = function()
    local font = vim.o.guifont
    local size = font:match ":h%d+"
    if size then K.font_size(size:sub(3)) end
  end
  vim.api.nvim_create_user_command("KittyFontSize", function(a) K.font_size(a.args) end, { nargs = "?" })
  vim.api.nvim_create_user_command("KittyFontUp", K.font_up, {})
  vim.api.nvim_create_user_command("KittyFontDown", K.font_down, {})
  vim.api.nvim_create_user_command("KittyLs", K.ls, {})
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "guifont",
    callback = guifontsize,
  })

  K.setup = function(_) return K end

  vim.api.nvim_create_autocmd("Signal", {
    group = vim.api.nvim_create_augroup("__signal_kitty_refocus", {}),
    pattern = "SIGUSR1",
    callback = function() K.focus() end,
  })
  function K.wakeup(launch) return KT:sh("wakeup", launch) .. " " .. vim.fn.getpid() end

  return K
end

return K
