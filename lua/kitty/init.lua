local K = {}
local defaults = {}

K.setup = function(cfg)
  cfg = vim.tbl_extend("keep", cfg or {}, defaults)

  local KT
  if cfg.from_current_win then
    local CW = require("kitty.current_win").setup()
    KT = CW.sub_window(cfg, cfg.from_current_win)
  else
    KT = require("kitty.term"):new(cfg)
  end
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

  K.setup = function(_)
    return K
  end

  return K
end
return K
