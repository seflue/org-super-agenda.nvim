local Date = require('org-super-agenda.date')

describe('Date helpers', function()
  it('detects today', function()
    local t = os.date('*t')
    local d = Date.new(t.year, t.month, t.day)
    assert.is_true(d:is_today())
  end)

  it('stringifies correctly', function()
    local d = Date.new(2025, 07, 23)
    assert.equals('2025-07-23', tostring(d))
  end)

  it('past vs. future', function()
    local past  = Date.parse('2000-01-01')
    local future = Date.parse('2999-12-31')
    assert.is_true(past:is_past())
    assert.is_false(future:is_past())
  end)
end)

