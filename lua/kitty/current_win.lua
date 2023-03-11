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

  -- TODO: mirror guifont? guifb, guibg
  vim.api.nvim_create_user_command("KittyFontSize", function(a)
    K.font_size(a.args)
  end, { nargs = "?" })
  vim.api.nvim_create_user_command("KittyFontUp", K.font_down, {})
  vim.api.nvim_create_user_command("KittyFontDown", K.font_up, {})
  vim.api.nvim_create_autocmd("OptionSet", {
    pattern = "guifont",
    callback = function()
      local font = vim.o.guifont
      local size = font:match "%d+$"
      if size then
        K.font_size(size)
      end
    end,
  })

  K.setup = function(_)
    return K
  end

  return K
end
return K
