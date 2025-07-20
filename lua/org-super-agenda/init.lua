-- org-super-agenda – entry point ------------------------------------------------
local cfg    = require('org-super-agenda.config')
local source = require('org-super-agenda.source')
local groups = require('org-super-agenda.groups')
local view   = require('org-super-agenda.view')

local M      = {}

function M.setup(opts)
  cfg.setup(opts or {})
  vim.api.nvim_create_user_command('OrgSuperAgenda', function() M.open() end, {})
end

function M.open(cursor_pos, opts)
  opts = opts or {}
  -- collect all headlines across configured org sources
  local items = source.collect_items()
  -- optional filter by TODO state
  if opts.todo_filter then
    local wanted = {}
    if type(opts.todo_filter) == 'string' then
      wanted[opts.todo_filter] = true
    elseif type(opts.todo_filter) == 'table' then
      for _, st in ipairs(opts.todo_filter) do wanted[st] = true end
    end
    if next(wanted) then
      local filtered = {}
      for _, it in ipairs(items) do
        if wanted[it.todo_state] then table.insert(filtered, it) end
      end
      items = filtered
    end
  end
  -- Group and render
  local grouped = groups.group_items(items)
  view.render(grouped, cursor_pos)
end

return M
