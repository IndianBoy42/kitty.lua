function get_mark(mark)
  local position = vim.api.nvim_buf_get_mark(0, mark)
  if position[1] == 0 then
    return nil
  end
  position[2] = position[2] + 1
  return position
end
function get_lines(start, stop)
  return vim.api.nvim_buf_get_lines(0, start - 1, stop, false)
end

function get_text(first_position, last_position)
  -- I don't understand why this is right, but everything else isn't.
  return vim.api.nvim_buf_get_text(
    0,
    first_position[1] - 1, -- row
    first_position[2] - 1, -- col
    last_position[1] - 1, -- row
    last_position[2], -- col
    {}
  )
end

local Repl = {}
-- TODO: Repl Mode (Code Snippet Running) with T

function Repl.setup(T)
  -- Options, state variables, etc
  T.filetypes = T.filetypes or require "kitty.repl.builtins"
  T.filetypes.default = T.filetypes.default or {
    cell_delimiter = "%%",
  }
  for key, value in pairs(T.filetypes) do
    T.filetypes[key] = setmetatable(value, T.filetypes.default)
  end
  T.repl_namespace = vim.api.nvim_create_namespace(T.title .. "_repl_highlights")
  T.previous_range_extmark1 = nil
  T.previous_ranges_extmarks = {}

  -- Functions
  function T:ft_opts()
    local _ft = self.ftype
    if _ft == nil then
      _ft = vim.bo.filetype
    end
    if self.filetypes[_ft] == nil then
      self.filetypes[_ft] = self.filetypes.default
    end
    return self.filetypes[_ft]
  end
  function T:start_repl()
    local send = self:ft_opts().start_repl
    if type(send) == "function" then
      send = send(self)
    end
    if send then
      self:send(send)
    end
  end
  function T:cell_delimiter_pattern()
    local o = self:ft_opts()
    if o.cell_delimiter_pattern == nil then
      o.cell_delimiter_pattern = vim.o.commentstring:gsub("%%s", o.cell_delimiter)
    end
    return o.cell_delimiter_pattern
  end
  function T:is_cell_delimiter(line)
    return string.match(line, vim.o.commentstring:gsub("%%s", self:ft_opts().cell_delimiter)) ~= nil
  end
  function T:highlight_cell_delimiter(color)
    vim.cmd([[highlight TCellDelimiterColor guifg=]] .. color .. [[ guibg=]] .. color)
    vim.cmd [[sign define TCellDelimiters linehl=TCellDelimiterColor text=> ]]
    vim.cmd("sign unplace * group=TCellDelimiters buffer=" .. vim.fn.bufnr())
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    for line_number, line in pairs(lines) do
      if self:is_cell_delimiter(line) then
        vim.api.nvim_buf_add_highlight(0, self.repl_namespace, "TCellDelimiterColor", line_number - 1, 0, -1)
      end
    end
  end
  function T:get_cell()
    local opts = {}
    opts.line1 = vim.fn.search(self:cell_delimiter_pattern(), "bcnW")
    opts.line2 = vim.fn.search(self:cell_delimiter_pattern(), "nW")
    -- line after delimiter or top of file
    opts.line1 = opts.line1 and opts.line1 + 1 or 1
    -- line before delimiter or bottom of file
    opts.line2 = opts.line2 and opts.line2 - 1 or -1
    return self:get_range("line", { opts.line1, 0 }, { opts.line2, 0 })
  end
  function T:prev_range_under_cursor()
    local cursor = vim.api.nvim_win_get_cursor(0)
    cursor[1] = cursor[1] - 1 -- mark-like to extmarks
    local marks = vim.api.nvim_buf_get_extmarks(0, self.repl_namespace, cursor, cursor, { details = true })
    return marks
  end
  function T:get_range(mode, p1, p2)
    -- TODO: memorize the range for repeating ranges
    self.previous_range_extmark1 = vim.api.nvim_buf_set_extmark(
      0,
      self.repl_namespace,
      p1[1],
      p1[2],
      { id = self.previous_range_extmark1, end_row = p2[1], end_col = p2[2] }
    )
    local prev_ranges = self:prev_range_under_cursor()
    for _, prev_range in ipairs(prev_ranges) do
      -- Find the smallest range
    end

    if mode == "line" then
      return get_lines(p1[1], p2[1])
    elseif mode == "char" then
      return get_text(p1, p2)
    end
  end
  function T:get_yanked(mode)
    return self:get_range(mode or "char", get_mark "[", get_mark "]")
  end
  function T:get_yanked_lines()
    return self:get_yanked "line"
  end
  function T:get_selected(mode)
    return self:get_range(mode or "char", get_mark "<", get_mark ">")
  end
  function T:get_selected_lines()
    return self:get_selected "line"
  end
  function T:get_current_line()
    return { vim.api.nvim_get_current_line() }
  end

  -- Can be used as operatorfunc
  function T:send_range(mode, p1, p2)
    local lines = {}
    if p1 and p2 then
      lines = self:get_range(mode, p1, p2)
    else
      local nvi = vim.api.nvim_get_mode().mode
      if nvi == "v" then
        lines = self:get_selected()
      elseif nvi == "V" then
        lines = self:get_selected_lines()
      elseif nvi == "i" then
        lines = self:current_line()
      else
        lines = self:get_yanked()
      end
    end

    return self:send_lines(lines)
  end
  function T:send_lines(lines)
    for _, line in ipairs(lines) do
      self:send(line .. "\r")
    end
  end
  function T:send_current_line()
    return self:send_lines(self:get_current_line())
  end
  function T:send_current_word()
    self:send_lines { vim.fn.expand "<cword>" }
  end
end

return Repl
