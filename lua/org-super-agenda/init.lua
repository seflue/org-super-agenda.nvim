-- org-super-agenda/init.lua (bootstrap & wiring)
local cfgmod     = require('org-super-agenda.config')
local Store      = require('org-super-agenda.app.store')
local Pipeline   = require('org-super-agenda.app.pipeline')
local Services   = require('org-super-agenda.app.services')

local SourcePort = require('org-super-agenda.adapters.neovim.source_orgmode')
local ViewPort   = require('org-super-agenda.adapters.neovim.view_float')

local M = {}

function M.setup(user)
  local cfg = cfgmod.setup(user or {})

  -- wire services
  Services.setup({
    cfg = cfg,
    store = Store,
    source = SourcePort,
    view = ViewPort,
    pipeline = Pipeline,
  })

  vim.api.nvim_create_user_command('OrgSuperAgenda', function()
    Services.agenda.open()
  end, {})
end

-- Expose a minimal API for internal adapters (used by actions)
M.refresh          = function(cur, opts) Services.agenda.refresh(cur, opts) end
M.on_close         = function() Services.agenda.on_close() end
M.toggle_duplicates= function() Services.agenda.toggle_duplicates() end
M.cycle_view       = function() Services.agenda.cycle_view() end
M.hide_current     = function() Services.agenda.hide_current() end
M.reset_hidden     = function() Services.agenda.reset_hidden() end
M.push_undo        = function(fn) Store.push_undo(fn) end
M.pop_undo         = function() return Store.pop_undo() end

return M

