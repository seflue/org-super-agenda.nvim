-- adapters/neovim/view_float.lua -- implements ViewPort
local hi      = require('org-super-agenda.adapters.neovim.highlight')
local get_cfg = require('org-super-agenda.config').get

local V = { _buf=nil, _win=nil, _prev_win=nil, _line_map={}, _ns = vim.api.nvim_create_namespace('OrgSuperAgenda') }

function V.is_open()
  return V._buf and vim.api.nvim_buf_is_valid(V._buf)
     and V._win and vim.api.nvim_win_is_valid(V._win)
end

function V.line_map() return V._line_map end
function V.prev_win() return V._prev_win end

local function add_hl(buf, row, col_start, col_end, entry)
  local group = entry[4] or hi.group(entry.state)
  vim.api.nvim_buf_add_highlight(buf, V._ns, group, row, col_start, col_end)
end

local function sizes(opts)
  local cfg = get_cfg()
  local ui  = vim.api.nvim_list_uis()[1]
  local fullscreen = opts and opts.fullscreen

  local left  = cfg.window.margin_left  or 0
  local right = cfg.window.margin_right or 0

  local w = fullscreen and ui.width  or math.floor(ui.width  * cfg.window.width)
  local h = fullscreen and ui.height or math.floor(ui.height * cfg.window.height)
  local border = fullscreen and (cfg.window.fullscreen_border or 'none') or cfg.window.border

  return {
    ui = ui,
    left = left, right = right,
    win_w = (fullscreen and ui.width or math.floor(ui.width * cfg.window.width)) - left - right,
    width = (fullscreen and ui.width or math.floor(ui.width * cfg.window.width)),
    height = (fullscreen and ui.height or math.floor(ui.height * cfg.window.height)),
    border = border,
    title  = cfg.window.title,
    title_pos = cfg.window.title_pos,
  }
end

local function draw_into(buf, win, producer, cursor, opts)
  hi.ensure()
  local sz  = sizes(opts)

  local rows, hls, new_map = producer(sz.win_w)

  rows[#rows + 1] = ''
  rows[#rows + 1] = '🔍  g? for help'
  hls[#hls + 1]   = { (#rows - 1), 0, -1, 'Comment', field='help' }

  for k in pairs(V._line_map) do V._line_map[k] = nil end
  for k, v in pairs(new_map) do V._line_map[k] = v end

  local pad = {}
  for _, l in ipairs(rows) do pad[#pad + 1] = string.rep(' ', sz.left) .. l .. string.rep(' ', sz.right) end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pad)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, V._ns, 0, -1)
  for _, h in ipairs(hls) do
    add_hl(buf, h[1], sz.left + h[2], h[3] == -1 and -1 or sz.left + h[3], h)
  end

  if cursor then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_set_cursor, win, cursor) end
    end)
  end
end

function V.render(producer, cursor, _mode, opts)
  hi.ensure()
  local cfg = get_cfg()
  local sz  = sizes(opts)

  local rows, hls, line_map = producer(sz.win_w)
  rows[#rows + 1] = ''
  rows[#rows + 1] = '🔍  g? for help'
  hls[#hls + 1]   = { (#rows - 1), 0, -1, 'Comment', field='help' }

  local buf = vim.api.nvim_create_buf(false, true)
  local pad = {}
  for _, l in ipairs(rows) do pad[#pad + 1] = string.rep(' ', sz.left) .. l .. string.rep(' ', sz.right) end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pad)
  vim.bo[buf].filetype, vim.bo[buf].modifiable = 'org', false
  vim.api.nvim_buf_set_name(buf, cfg.window.title)

  for _, h in ipairs(hls) do
    add_hl(buf, h[1], sz.left + h[2], h[3] == -1 and -1 or sz.left + h[3], h)
  end

  -- Reuse existing window if still valid, otherwise create new one
  local win
  if V._win and vim.api.nvim_win_is_valid(V._win) then
    win = V._win
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_set_current_win(win)
  else
    -- Store current window before creating floating window (for Tab keymap)
    V._prev_win = vim.api.nvim_get_current_win()
    win = vim.api.nvim_open_win(buf, true, {
      relative='editor', style='minimal',
      width = sz.width, height = sz.height,
      col = math.floor((sz.ui.width  - sz.width ) / 2),
      row = math.floor((sz.ui.height - sz.height) / 2),
      border = sz.border, title = sz.title, title_pos = sz.title_pos,
    })
  end
  vim.api.nvim_win_set_option(win, 'wrap', false)
  vim.api.nvim_win_set_option(win, 'cursorline', true)

  V._buf, V._win = buf, win
  for k in pairs(V._line_map) do V._line_map[k] = nil end
  for k, v in pairs(line_map) do V._line_map[k] = v end

  -- bind keymaps
  local actions = require('org-super-agenda.adapters.neovim.actions')
  local function reopen(cur) require('org-super-agenda').refresh(cur, { fullscreen = opts and opts.fullscreen or false }) end
  actions.set_keymaps(buf, win, V._line_map, reopen)

  if cursor then pcall(vim.api.nvim_win_set_cursor, win, cursor) end
end

function V.update(producer, cursor, _mode, opts)
  -- If window exists but buffer is invalid, reuse window with new buffer
  if V._win and vim.api.nvim_win_is_valid(V._win) and (not V._buf or not vim.api.nvim_buf_is_valid(V._buf)) then
    V.render(producer, cursor, _mode, opts)
  elseif V.is_open() then
    draw_into(V._buf, V._win, producer, cursor, opts)
  else
    V.render(producer, cursor, _mode, opts)
  end
end

return V

