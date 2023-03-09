local K = {}
local defaults = {
  attach_to_current_win = true,
}
K.setup = function(cfg)
  cfg = vim.tbl_extend("keep", cfg or {}, defaults)

  local Term = require "kitty.term"
  local KT = Term:new(cfg)
  K.instance = KT

  -- Create the illusion of the global singleton, so can use . rather than :
  setmetatable(K, {
    __index = function(m, k)
      local ret = KT[k]
      if type(ret) == "function" then
        local f = function(...)
          return ret(KT, ...)
        end
        m[k] = f
        return f
      else
        return ret
      end
    end,
  })

  K.font_up = function()
    K.font_size "+1"
  end
  K.font_down = function()
    K.font_size "-1"
  end

  vim.api.nvim_create_user_command("KittyFontUp", function(a)
    K.font_size(a.args)
  end)
  vim.api.nvim_create_user_command("KittyFontUp", K.font_down)
  vim.api.nvim_create_user_command("KittyFontDown", K.font_up)
  -- TODO: mirror guifont? guifb, guibg

  return K
end
return K
