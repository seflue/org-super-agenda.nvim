local osa = require('org-super-agenda')
local config = require('org-super-agenda.config')

describe('hidden items', function()
  before_each(function()
    osa._hidden = {}
  end)

  it('clears hidden items on close when not persistent', function()
    osa._hidden['a:1'] = true
    config.setup({ persist_hidden = false })
    osa.on_close()
    assert.is_nil(next(osa._hidden))
  end)

  it('keeps hidden items on close when persistent', function()
    osa._hidden['a:1'] = true
    config.setup({ persist_hidden = true })
    osa.on_close()
    assert.is_true(osa._hidden['a:1'])
    config.setup({ persist_hidden = false })
  end)
end)
