-- adapters/neovim/actions.lua
local utils     = require('org-super-agenda.adapters.neovim.utils')
local config    = require('org-super-agenda.config')
local Services  = require('org-super-agenda.app.services')
local Store     = require('org-super-agenda.app.store')

local A = {}
local function get_cfg() return config.get() end
local function key_for_hl(hl)
  return string.format('%s:%s', hl.file.filename or '', hl.position and hl.position.start_line or 0)
end

-- === helpers ===
local function snapshot_headline(hl)
  local bufnr = vim.fn.bufnr(hl.file.filename)
  if bufnr == -1 then bufnr = vim.fn.bufadd(hl.file.filename) end
  if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local start = hl.position.start_line
  while start > 1 and not lines[start]:match("^%*+") do start = start - 1 end
  local lvl  = #(lines[start]:match("^(%*+)"))
  local stop = #lines
  for i = start + 1, #lines do
    local s = lines[i]:match("^(%*+)")
    if s and #s <= lvl then stop = i - 1; break end
  end
  return { bufnr = bufnr, start = start, stop = stop, seg = vim.list_slice(lines, start, stop) }
end

local function make_restore(snap)
  return function()
    vim.api.nvim_buf_set_lines(snap.bufnr, snap.start - 1, snap.stop, false, snap.seg)
    vim.api.nvim_buf_call(snap.bufnr, function() vim.cmd('silent noautocmd write') end)
  end
end

local function with_headline(line_map, cb)
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = line_map[cur[1]]
  if not (it and it.file and it._src_line) then
    vim.notify('No entry under cursor', vim.log.levels.WARN)
    return
  end
  local ok, api_root = pcall(require, 'orgmode.api'); if not ok then return end
  local org_api = api_root.load and api_root or api_root.org
  local file    = org_api.load(it.file); if vim.islist(file) then file = file[1] end
  if not (file and file.get_headline_on_line) then return end
  local hl = file:get_headline_on_line(it._src_line)
  if not hl then return end
  cb(cur, hl)
end

local function preview_headline(line_map)
  with_headline(line_map, function(_, hl)
    local lines = {}
    if hl._section and hl._section.get_lines then
      lines = hl._section:get_lines()
    elseif hl.position and hl.position.start_line and hl.position.end_line then
      local bufnr = vim.fn.bufnr(hl.file.filename)
      if bufnr == -1 then bufnr = vim.fn.bufadd(hl.file.filename) end
      if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
      lines = vim.api.nvim_buf_get_lines(bufnr, hl.position.start_line - 1, hl.position.end_line, false)
    end
    if #lines == 0 then return end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].filetype = 'org'
    local ui  = vim.api.nvim_list_uis()[1]
    local h   = math.min(#lines + 2, math.floor(ui.height * 0.6))
    local w   = math.min(80, math.floor(ui.width * 0.8))
    local win = vim.api.nvim_open_win(buf, true, {
      relative='editor', style='minimal', border='rounded',
      width=w, height=h, col=math.floor((ui.width - w)/2), row=math.floor((ui.height - h)/2),
      title='Org Preview',
    })
    local function close() if vim.api.nvim_win_is_valid(win) then vim.api.nvim_win_close(win, true) end end
    vim.keymap.set('n', 'q', close, { buffer = buf, silent = true })
  end)
end

local function apply_with_undo(cur, hl, op_fn)
  local snap = snapshot_headline(hl)
  Store.push_undo(make_restore(snap))
  local p = op_fn()
  vim.defer_fn(function()
    if p and type(p.next) == 'function' then p:next(function() Services.agenda.refresh(cur) end)
    else Services.agenda.refresh(cur) end
  end, 10)
end

-- === keymaps ===
function A.set_keymaps(buf, win, line_map, reopen)
  local cfg = get_cfg()

  -- close
  local function wipe()
    if vim.api.nvim_buf_is_valid(buf) then pcall(vim.api.nvim_buf_delete, buf, { force = true }) end
    require('org-super-agenda').on_close()
  end
  for _, k in ipairs({ 'q', '<Esc>' }) do vim.keymap.set('n', k, wipe, { buffer = buf, silent = true }) end

  -- open file
  vim.keymap.set('n', '<CR>', function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(hl.file.filename))
      vim.api.nvim_win_set_cursor(0, { hl.position.start_line, 0 })
      local filebuf = vim.api.nvim_get_current_buf()
      pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
      vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer = filebuf, once = true,
        callback = function()
          vim.schedule(function()
            pcall(vim.api.nvim_buf_delete, filebuf, { force = true })
            reopen(cur)
          end)
        end,
      })
    end)
  end, { buffer = buf, silent = true })

  -- reschedule / deadline
  vim.keymap.set('n', cfg.keymaps.reschedule, function()
    with_headline(line_map, function(cur, hl)
      local snap = snapshot_headline(hl)
      local p = hl:set_scheduled()
      local function after() Store.push_undo(make_restore(snap)); Services.agenda.refresh(cur) end
      if p and type(p.next) == 'function' then p:next(after) else after() end
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.set_deadline, function()
    with_headline(line_map, function(cur, hl)
      local snap = snapshot_headline(hl)
      local p = hl:set_deadline()
      local function after() Store.push_undo(make_restore(snap)); Services.agenda.refresh(cur) end
      if p and type(p.next) == 'function' then p:next(after) else after() end
    end)
  end, { buffer = buf, silent = true })

  -- toggle Other
  if cfg.keymaps.toggle_other and cfg.keymaps.toggle_other ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_other, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local c   = get_cfg()
      require('org-super-agenda.config').setup({ show_other_group = not c.show_other_group })
      Services.agenda.refresh(cur)
    end, { buffer = buf, silent = true })
  end

  -- ✅ toggle duplicates (this was missing)
  if cfg.keymaps.toggle_duplicates and cfg.keymaps.toggle_duplicates ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_duplicates, function()
      Services.agenda.toggle_duplicates()
    end, { buffer = buf, silent = true })
  end

  -- priorities
  local function make_set_priority(prio)
    return function()
      with_headline(line_map, function(cur, hl)
        apply_with_undo(cur, hl, function() return hl:set_priority(prio) end)
      end)
    end
  end
  vim.keymap.set('n', cfg.keymaps.priority_A, make_set_priority('A'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_B, make_set_priority('B'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_C, make_set_priority('C'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_clear, make_set_priority(''), { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_up, function()
    with_headline(line_map, function(cur, hl)
      apply_with_undo(cur, hl, function() return hl:priority_up() end)
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_down, function()
    with_headline(line_map, function(cur, hl)
      apply_with_undo(cur, hl, function() return hl:priority_down() end)
    end)
  end, { buffer = buf, silent = true })

  -- Quick TODO filters
  for _, st in ipairs(get_cfg().todo_states or {}) do
    if st.keymap and st.keymap ~= '' and st.name then
      vim.keymap.set('n', st.keymap, function()
        local cur = vim.api.nvim_win_get_cursor(0)
        Services.agenda.refresh(cur, { todo_filter = st.name })
      end, { buffer = buf, silent = true })
    end
  end

  if cfg.keymaps.filter_reset and cfg.keymaps.filter_reset ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_reset, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      Services.agenda.refresh(cur, { todo_filter = nil, headline_filter = nil, query = nil })
    end, { buffer = buf, silent = true })
  end

  -- live filter (exact/fuzzy)
  local function live_filter(fuzzy)
    local cur, query = vim.api.nvim_win_get_cursor(0), ''
    local function apply()
      Services.agenda.refresh(cur, { headline_filter = query, headline_fuzzy = fuzzy })
      vim.api.nvim_echo({ { 'Filter: ' .. query } }, false, {}); vim.cmd('redraw')
    end
    vim.api.nvim_echo({ { 'Filter: ' } }, false, {})
    while true do
      local ok, c = pcall(vim.fn.getcharstr); if not ok then break end
      if c == '\027' or c == '\013' then break end
      local bs = vim.api.nvim_replace_termcodes('<BS>', true, false, true)
      if c == '\008' or c == '\127' or c == bs then query = query:sub(1, -2) else query = query .. c end
      apply()
    end
    vim.api.nvim_echo({}, false, {})
  end
  if cfg.keymaps.filter and cfg.keymaps.filter ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter, function() live_filter(false) end, { buffer = buf, silent = true, nowait = true })
  end
  if cfg.keymaps.filter_fuzzy and cfg.keymaps.filter_fuzzy ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_fuzzy, function() live_filter(true) end, { buffer = buf, silent = true, nowait = true })
  end

  -- query input
  if cfg.keymaps.filter_query and cfg.keymaps.filter_query ~= '' then
    vim.keymap.set('n', cfg.keymaps.filter_query, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      local q = vim.fn.input('Query: ')
      Services.agenda.refresh(cur, { query = q })
    end, { buffer = buf, silent = true })
  end

  -- preview
  if cfg.keymaps.preview and cfg.keymaps.preview ~= '' then
    vim.keymap.set('n', cfg.keymaps.preview, function() preview_headline(line_map) end, { buffer = buf, silent = true })
  end

  -- hide/reset hidden
  if cfg.keymaps.hide_item and cfg.keymaps.hide_item ~= '' then
    vim.keymap.set('n', cfg.keymaps.hide_item, function() require('org-super-agenda').hide_current() end, { buffer = buf, silent = true })
  end
  if cfg.keymaps.reset_hidden and cfg.keymaps.reset_hidden ~= '' then
    vim.keymap.set('n', cfg.keymaps.reset_hidden, function()
      require('org-super-agenda').reset_hidden()
      Services.agenda.refresh(vim.api.nvim_win_get_cursor(0))
    end, { buffer = buf, silent = true })
  end

  -- cycle todo (manage sticky DONE visibility)
  vim.keymap.set('n', cfg.keymaps.cycle_todo, function()
    with_headline(line_map, function(cur, hl)
      local seq = {}
      for _, s in ipairs(get_cfg().todo_states or {}) do seq[#seq + 1] = s.name end
      if #seq == 0 then return end
      local idx = 0
      for i, v in ipairs(seq) do if v == (hl.todo_value or '') then idx = i; break end end
      local next_state = seq[idx % #seq + 1]
      local bufnr, created = vim.fn.bufnr(hl.file.filename), false
      if bufnr == -1 then bufnr = vim.fn.bufadd(hl.file.filename); created = true end
      if not vim.api.nvim_buf_is_loaded(bufnr) then vim.fn.bufload(bufnr) end
      local lnum = (hl.position and hl.position.start_line or 1) - 1; if lnum < 0 then return end
      local line = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]; if not line then return end

      local stars, _, rest = line:match('^(%*+)%s+([A-Z]+)%s+(.*)$')
      if not stars then stars, rest = line:match('^(%*+)%s+(.*)$') end
      if not stars then return end

      local new_line = (next_state == '') and (stars .. ' ' .. rest) or (stars .. ' ' .. next_state .. ' ' .. rest)
      vim.api.nvim_buf_set_lines(bufnr, lnum, lnum + 1, false, { new_line })
      vim.api.nvim_buf_call(bufnr, function() vim.cmd('silent noautocmd write') end)
      if created and vim.fn.bufwinnr(bufnr) == -1 then vim.api.nvim_buf_delete(bufnr, { force = true }) end

      local key = key_for_hl(hl)
      if next_state == 'DONE' then Store.sticky_add(key) else Store.sticky_remove(key) end
      Services.agenda.refresh(cur)
    end)
  end, { buffer = buf, silent = true })

  -- reload
  vim.keymap.set('n', cfg.keymaps.reload, function()
    local cur = vim.api.nvim_win_get_cursor(0)
    Services.agenda.refresh(cur)
  end, { buffer = buf, silent = true })

  -- refile
  if cfg.keymaps.refile and cfg.keymaps.refile ~= '' then
    vim.keymap.set('n', cfg.keymaps.refile, function()
      with_headline(line_map, function(_, hl)
        local pos = hl.position
        if not (pos and pos.start_line and pos.end_line and hl.level) then
          return vim.notify('Cannot refile: missing position info from orgmode.', vim.log.levels.WARN)
        end
        Services.refile_start(hl.file.filename, pos.start_line, pos.end_line, hl.level)
      end)
    end, { buffer = buf, silent = true })
  end

  -- cycle view
  if cfg.keymaps.cycle_view and cfg.keymaps.cycle_view ~= '' then
    vim.keymap.set('n', cfg.keymaps.cycle_view, function() require('org-super-agenda').cycle_view() end, { buffer = buf, silent = true })
  end

  -- undo
  vim.keymap.set('n', cfg.keymaps.undo, function()
    Store.pop_undo()
    Services.agenda.refresh(vim.api.nvim_win_get_cursor(0))
  end, { buffer = buf, silent = true })

  -- help
  vim.keymap.set('n', 'g?', utils.show_help, { buffer = buf, silent = true })
end

return A

