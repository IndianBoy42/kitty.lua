local Repl = {}
-- TODO: Repl Mode (Code Snippet Running) with T

function Repl.setup(T)
  -- Options, state variables, etc

  -- Functions
  function T:repl()
    local _ft = self.ftype
    if _ft == nil then
      _ft = vim.bo.filetype
    end
    return self[_ft] or {}
  end
  function T:cell_delimiter()
    return self:repl().comment_character .. " %%"
  end
  -- function T:highlight_cell_delimiter(color)
  --   vim.cmd([[highlight TCellDelimiterColor guifg=]] .. color .. [[ guibg=]] .. color)
  --   vim.cmd [[sign define TCellDelimiters linehl=TCellDelimiterColor text=> ]]
  --   vim.cmd("sign unplace * group=TCellDelimiters buffer=" .. vim.fn.bufnr())
  --   local lines = vim.fn.getline(0, "$")
  --   for line_number, line in pairs(lines) do
  --     if line:find(self:cell_delimiter()) then
  --       vim.cmd(
  --         "sign place 1 line="
  --           .. line_number
  --           .. " group=TCellDelimiters name=TCellDelimiters buffer="
  --           .. vim.fn.bufnr()
  --       )
  --     end
  --   end
  -- end
  function T:send_cell()
    local opts = {}
    opts.line1 = vim.fn.search(self:cell_delimiter(), "bcnW")
    opts.line2 = vim.fn.search(self:cell_delimiter(), "nW")
    -- line after delimiter or top of file
    opts.line1 = opts.line1 and opts.line1 + 1 or 1
    -- line before delimiter or bottom of file
    opts.line2 = opts.line2 and opts.line2 - 1 or vim.fn.line "$"
    if opts.line1 <= opts.line2 then
      return self:send_range(opts)
    else
      return self:send_file()
    end
  end

  function T:send_range(opts)
    local startline = opts.line1
    local endline = opts.line2
    -- save registers for restore
    local rv = vim.fn.getreg '"'
    local rt = vim.fn.getregtype '"'
    -- yank range silently
    vim.cmd("silent! " .. startline .. "," .. endline .. "yank")
    local payload = vim.fn.getreg '"'
    -- restore
    self:send(payload)
    vim.fn.setreg('"', rv, rt)
  end

  function T:send_current_line()
    local payload = vim.api.nvim_get_current_line()
    local prefix = self:repl().line_delimiter_start
    local suffix = self:repl().line_delimiter_end
    self:send(prefix .. payload .. suffix .. "\n")
  end

  function T:send_current_word()
    self:send(vim.fn.expand "<cword>")
  end

  function T:get_selection()
    local s_start = vim.fn.getpos "'<"
    local s_end = vim.fn.getpos "'>"
    local n_lines = math.abs(s_end[2] - s_start[2]) + 1
    local lines = vim.api.nvim_buf_get_lines(0, s_start[2] - 1, s_end[2], false)
    lines[1] = string.sub(lines[1], s_start[3], -1)
    if n_lines == 1 then
      lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3] - s_start[3] + 1)
    else
      lines[n_lines] = string.sub(lines[n_lines], 1, s_end[3])
    end
    return table.concat(lines, "\n")
  end

  function T:send_selection()
    self:send(self:get_selection())
  end
end

return Repl
