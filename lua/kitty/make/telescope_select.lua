return function(topts)
  topts = topts or require("telescope.themes").get_cursor() -- get_dropdown
  if type(topts) == "string" then topts = require("telescope.themes")[topts]() end
  local conf = require("telescope.config").values
  return function(items, opts, on_choice)
    opts = opts or {}
    local prompt = opts.prompt or ""
    local format_item = opts.format_item or tostring

    require("telescope.pickers")
      .new(topts, {
        prompt_title = prompt,
        finder = require("telescope.finders").new_table {
          results = items, -- TODO:
          entry_maker = function(entry)
            local str = format_item(entry)
            -- local str = function(tbl)
            --   utils.dump(tbl)
            --   return format_item(tbl.value)
            -- end

            return {
              value = entry,
              display = str,
              ordinal = str,
            }
          end,
        },
        sorter = conf.generic_sorter(topts),
        attach_mappings = function(prompt_bufnr, map)
          require("telescope.actions").select_default:replace(function()
            require("telescope.actions").close(prompt_bufnr)
            local selection = require("telescope.actions.state").get_selected_entry()
            on_choice(selection.value, selection.index)
          end)
          return true
        end,
      })
      :find()
  end
end
