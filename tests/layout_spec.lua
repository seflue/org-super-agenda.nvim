local layout = require('org-super-agenda.layout')
local Date   = require('org-super-agenda.date')
local Item   = require('org-super-agenda.org_item')
require('org-super-agenda.highlight').ensure()

describe('layout.build', function()
  it('emits rows and line map', function()
    local it = Item.new{
      level = 1,
      headline = 'Test',
      tags = {'x'},
      todo_state = 'TODO',
      priority = 'A',
      file = vim.fn.tempname() .. '.org',
      scheduled = Date.new(2025,7,23),
    }
    local g = { { name = 'Grp', items = { it } } }
    local rows, hls, map = layout.build(g, 80)
    assert.is_true(#rows >= 3)
    assert.equals('* Grp', rows[2])
    assert.same(it, map[3])
    assert.is_true(#hls > 0)
  end)
end)
