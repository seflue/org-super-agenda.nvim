local config = require('org-super-agenda.config')

describe('config.setup', function()
  local defaults = vim.deepcopy(config.defaults)

  after_each(function()
    config.setup(vim.deepcopy(defaults))
  end)

  it('overrides values', function()
    config.setup({ upcoming_days = 5, keymaps = { reload = 'x' } })
    local cfg = config.get()
    assert.equals(5, cfg.upcoming_days)
    assert.equals('x', cfg.keymaps.reload)
  end)
end)
