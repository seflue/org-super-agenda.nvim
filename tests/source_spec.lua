local config = require('org-super-agenda.config')

local function fake_file(name)
  local file = { filename = name }
  function file:reload() return self end
  file.headlines = {
    {
      title = 'h',
      level = 1,
      tags = {},
      priority = '',
      todo_value = 'TODO',
      scheduled = nil,
      deadline = nil,
      properties = {},
      file = file,
      position = { start_line = 1 },
    },
  }
  return file
end

local function with_files(names, fn)
  package.loaded['org-super-agenda.source'] = nil
  package.loaded['orgmode.api'] = nil
  package.preload['orgmode.api'] = function()
    local list = {}
    for _, n in ipairs(names) do
      table.insert(list, fake_file(n))
    end
    local function load() return list end
    return { load = load, org = { load = load } }
  end
  fn(require('org-super-agenda.source'))
end

describe('file exclusion', function()
  local defaults = vim.deepcopy(config.get())
  after_each(function() config.setup(vim.deepcopy(defaults)) end)

  it('skips files listed in exclude_files', function()
    with_files({ '/tmp/a.org', '/tmp/b.org' }, function(source)
      config.setup({ org_files = { '/tmp/a.org', '/tmp/b.org' }, exclude_files = { '/tmp/a.org' } })
      local items = source.collect_items()
      assert.equals(1, #items)
      assert.equals('/tmp/b.org', items[1].file)
    end)
  end)

  it('skips files under exclude_directories', function()
    with_files({ '/tmp/a.org', '/tmp/sub/b.org' }, function(source)
      config.setup({ org_files = { '/tmp/a.org', '/tmp/sub/b.org' }, exclude_directories = { '/tmp/sub' } })
      local items = source.collect_items()
      assert.equals(1, #items)
      assert.equals('/tmp/a.org', items[1].file)
    end)
  end)
end)
