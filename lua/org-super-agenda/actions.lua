-- org-super-agenda.actions ---------------------------------------------------
local utils   = require('org-super-agenda.utils')
local config  = require('org-super-agenda.config')
local view    = require('org-super-agenda.view')
local A       = {}
local get_cfg = config.get

local function with_headline(_, cb)
  local lm  = view.line_map()
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = lm[cur[1]]
  if not (it and it.file and it._src_line) then
    vim.notify('Kein Eintrag unter dem Cursor', vim.log.levels.WARN)
    return
  end

  local bufnr = vim.fn.bufnr(it.file)
  if bufnr == -1 then
    bufnr = vim.fn.bufadd(it.file)
    vim.fn.bufload(bufnr)
  end

  local ok, api_root = pcall(require, 'orgmode.api'); if not ok then return end
  local org_api = api_root.load and api_root or api_root.org
  local file    = org_api.load(it.file); if vim.islist(file) then file = file[1] end
  if not (file and file.get_headline_on_line) then return end

  local hl = file:get_headline_on_line(it._src_line)
  if not hl then return end
  cb(cur, hl)
end

function A.set_keymaps(buf, win, line_map, reopen)
  local cfg = get_cfg()

  -------------------------------------------------------------------------
  -- wipe / close ----------------------------------------------------------
  local function wipe()
    if vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end
  for _, k in ipairs({ 'q', '<Esc>' }) do
    vim.keymap.set('n', k, wipe, { buffer = buf, silent = true })
  end

  -------------------------------------------------------------------------
  -- jump into org file ----------------------------------------------------
  vim.keymap.set('n', '<CR>', function()
    with_headline(line_map, function(cur, hl)
      local agendabuf = vim.api.nvim_get_current_buf()
      vim.cmd('edit ' .. vim.fn.fnameescape(hl.file.filename))
      vim.api.nvim_win_set_cursor(0, { hl.position.start_line, 0 })

      local filebuf = vim.api.nvim_get_current_buf()
      pcall(vim.api.nvim_buf_delete, agendabuf, { force = true })
      vim.api.nvim_create_autocmd('BufWinLeave', {
        buffer   = filebuf,
        once     = true,
        callback = function()
          vim.schedule(function()
            pcall(vim.api.nvim_buf_delete, filebuf, { force = true })
            reopen(cur)
          end)
        end,
      })
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- reschedule -----------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.reschedule, function()
    with_headline(line_map, function(cur, hl)
      local p = hl:set_scheduled()
      if p and type(p.next) == 'function' then
        p:next(function() require('org-super-agenda').refresh(cur) end)
      else
        require('org-super-agenda').refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- deadline -------------------------------------------------------------
  vim.keymap.set('n', cfg.keymaps.set_deadline, function()
    with_headline(line_map, function(cur, hl)
      local p = hl:set_deadline()
      if p and type(p.next) == 'function' then
        p:next(function() require('org-super-agenda').refresh(cur) end)
      else
        require('org-super-agenda').refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- toggle Other group --------------------------------------------------
  if cfg.keymaps.toggle_other and cfg.keymaps.toggle_other ~= '' then
    vim.keymap.set('n', cfg.keymaps.toggle_other, function()
      local cur = vim.api.nvim_win_get_cursor(0)
      config.setup({ show_other_group = not get_cfg().show_other_group })
      require('org-super-agenda').refresh(cur)
    end, { buffer = buf, silent = true })
  end

  ------------------------------------------------------------------------
  -- Priorities -----------------------------------------------------------
  local function do_refresh(cur)
    require('org-super-agenda').refresh(cur)
  end

  local function make_set_priority(prio)
    return function()
      with_headline(line_map, function(cur, hl)
        local p = hl:set_priority(prio)
        if p and type(p.next) == 'function' then
          p:next(function() do_refresh(cur) end)
        else
          do_refresh(cur)
        end
      end)
    end
  end

  vim.keymap.set('n', cfg.keymaps.priority_A, make_set_priority('A'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_B, make_set_priority('B'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_C, make_set_priority('C'), { buffer = buf, silent = true })
  vim.keymap.set('n', cfg.keymaps.priority_clear, make_set_priority(''), { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_up, function()
    with_headline(line_map, function(cur, hl)
      local p = hl:priority_up()
      if p and type(p.next) == 'function' then
        p:next(function() do_refresh(cur) end)
      else
        do_refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  vim.keymap.set('n', cfg.keymaps.priority_down, function()
    with_headline(line_map, function(cur, hl)
      local p = hl:priority_down()
      if p and type(p.next) == 'function' then
        p:next(function() do_refresh(cur) end)
      else
        do_refresh(cur)
      end
    end)
  end, { buffer = buf, silent = true })

  ------------------------------------------------------------------------
  -- Help ----------------------------------------------------------------
  vim.keymap.set('n', 'g?', utils.show_help, { buffer = buf, silent = true })
end

return A
