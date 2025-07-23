local utils = require('org-super-agenda.utils')

describe('utils.truncate', function()
  it('returns same string if shorter', function()
    assert.equals('abc', utils.truncate('abc', 10))
  end)

  it('cuts and keeps length', function()
    assert.equals('ab', utils.truncate('abcd', 2))
  end)
end)


describe('utils.expand and in_dirs', function()
  it('expands tilde', function()
    local home = vim.fn.expand('$HOME')
    assert.equals(home .. '/x', utils.expand('~/x'))
  end)

  it('checks directories', function()
    assert.is_true(utils.in_dirs('/a/b', {'/a'}))
    assert.is_nil(utils.in_dirs('/a/b', {'/c'}))
  end)
end)

describe('utils.get_org_files', function()
  it('recursively finds .org files', function()
    local tmp = vim.fn.tempname()
    vim.fn.mkdir(tmp .. '/sub', 'p')
    local f1 = tmp .. '/a.org'
    local f2 = tmp .. '/sub/b.org'
    io.open(f1, 'w'):close()
    io.open(f2, 'w'):close()
    local list = utils.get_org_files(tmp)
    table.sort(list)
    assert.same({f1, f2}, list)
  end)
end)
