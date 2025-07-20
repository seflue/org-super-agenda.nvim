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

function M.open(cursor_pos)
  -- collect all headlines across configured org sources
  local items = source.collect_items()
  -- Group and render (no pre‑filtering; group filters will take care of relevance)
  local grouped = groups.group_items(items)
  view.render(grouped, cursor_pos)
end

return M
