-- tests/groups_spec.lua -------------------------------------------------
local groups = require('org-super-agenda.groups')
local cfg    = require('org-super-agenda.config')
local Date   = require('org-super-agenda.date')
local Item   = require('org-super-agenda.org_item')

local function item(o)
  return Item.new(vim.tbl_extend('force', {
    level      = 1,
    tags       = {},
    priority   = '',
    file       = 'x.org',
    _src_line  = 1,
  }, o))
end

describe('group_items', function()
  it('puts DONE tasks only into Other/none', function()
    local raw = {
      item{ headline = 'done‑task', todo_state = 'DONE' },
    }
    local g = groups.group_items(raw)
    for _, grp in ipairs(g) do
      if grp.name ~= cfg.get().other_group_name then
        assert.is_true(#grp.items == 0)
      end
    end
  end)

  it('respects allow_duplicates=false', function()
    cfg.setup({
      allow_duplicates = false,
      show_other_group = false,
      groups = {
        { name = 'A', matcher = function(it) return it.a end },
        { name = 'B', matcher = function(it) return it.b end },
      },
    })
    local raw = { item{ a = true, b = true } }
    local g = groups.group_items(raw)
    local count = 0
    for _, grp in ipairs(g) do
      if #grp.items > 0 then
        count = count + 1
        assert.equals('A', grp.name)
      end
    end
    assert.equals(1, count)
  end)

  it('allows duplicates when enabled', function()
    cfg.setup({
      allow_duplicates = true,
      show_other_group = false,
      groups = {
        { name = 'A', matcher = function(it) return it.a end },
        { name = 'B', matcher = function(it) return it.b end },
      },
    })
    local raw = { item{ a = true, b = true } }
    local g = groups.group_items(raw)
    local found = {}
    for _, grp in ipairs(g) do
      if #grp.items > 0 then
        table.insert(found, grp.name)
      end
    end
    table.sort(found)
    assert.same({ 'A', 'B' }, found)
  end)

end)

