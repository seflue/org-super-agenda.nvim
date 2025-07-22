-- org-super-agenda.view ------------------------------------------------------
local hi      = require('org-super-agenda.highlight')
local layout  = require('org-super-agenda.layout')
local get_cfg = require('org-super-agenda.config').get

local V       = {}

-- internal State --------------------------------------------------------------
V._buf        = nil
V._win        = nil
V._line_map   = {}
V._ns         = vim.api.nvim_create_namespace('OrgSuperAgenda')

function V.is_open()
  return V._buf and vim.api.nvim_buf_is_valid(V._buf)
      and V._win and vim.api.nvim_win_is_valid(V._win)
end

function V.line_map()
  return V._line_map
end

local function write_into_existing(buf, win, groups, cursor)
  hi.ensure()
  local cfg                     = get_cfg()
  local ui                      = vim.api.nvim_list_uis()[1]
  local left                    = cfg.window.margin_left or 0
  local right                   = cfg.window.margin_right or 0
  local win_w                   = math.floor(ui.width * cfg.window.width) - left - right

  -- build layout
  local rows, hls, new_line_map = layout.build(groups, win_w)

  -- hint line -----------------------------------------------------------
  local hint                    = '🔍  g? for help'
  rows[#rows + 1]               = ''
  rows[#rows + 1]               = hint
  hls[#hls + 1]                 = { (#rows - 1), 0, -1, 'Comment' } -- (#rows-1) b/c 0-index for hl

  -- mutate V._line_map in place (keymaps captured this table)
  for k in pairs(V._line_map) do V._line_map[k] = nil end
  for k, v in pairs(new_line_map) do V._line_map[k] = v end

  -- update buffer lines -------------------------------------------------
  local pad = {}
  for _, l in ipairs(rows) do
    pad[#pad + 1] = string.rep(' ', left) .. l .. string.rep(' ', right)
  end
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pad)
  vim.bo[buf].modifiable = false

  -- clear & re-add highlights ------------------------------------------
  vim.api.nvim_buf_clear_namespace(buf, V._ns, 0, -1)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(
      buf, V._ns, h[4],
      h[1], left + h[2],
      h[3] == -1 and -1 or left + h[3]
    )
  end

  -- restore cursor ------------------------------------------------------
  if cursor then
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(win) then
        pcall(vim.api.nvim_win_set_cursor, win, cursor)
      end
    end)
  end
end

-- public: initial render (creates float) --------------------------------------
function V.render(groups, cursor)
  hi.ensure()
  local cfg                 = get_cfg()
  local ui                  = vim.api.nvim_list_uis()[1]
  local left                = cfg.window.margin_left or 0
  local right               = cfg.window.margin_right or 0
  local win_w               = math.floor(ui.width * cfg.window.width) - left - right

  -- layout
  local rows, hls, line_map = layout.build(groups, win_w)

  -- hint
  local hint                = '🔍  g? for help'
  rows[#rows + 1]           = ''
  rows[#rows + 1]           = hint
  hls[#hls + 1]             = { (#rows - 1), 0, -1, 'Comment' }

  -- buffer
  local buf                 = vim.api.nvim_create_buf(false, true)
  local pad                 = {}
  for _, l in ipairs(rows) do
    pad[#pad + 1] = string.rep(' ', left) .. l .. string.rep(' ', right)
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, pad)
  vim.bo[buf].filetype   = 'org'
  vim.bo[buf].modifiable = false
  vim.api.nvim_buf_set_name(buf, cfg.window.title)

  -- hi
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(
      buf, V._ns, h[4],
      h[1], left + h[2],
      h[3] == -1 and -1 or left + h[3]
    )
  end

  -- window
  local h = math.floor(ui.height * cfg.window.height)
  local w = win_w + left + right
  local win = vim.api.nvim_open_win(buf, true, {
    relative  = 'editor',
    style     = 'minimal',
    width     = w,
    height    = h,
    col       = math.floor((ui.width - w) / 2),
    row       = math.floor((ui.height - h) / 2),
    border    = cfg.window.border,
    title     = cfg.window.title,
    title_pos = cfg.window.title_pos,
  })
  vim.api.nvim_win_set_option(win, 'wrap', false)
  -- TODO: make this configurable
  vim.api.nvim_win_set_option(win, 'cursorline', true)


  -- remember state
  V._buf = buf
  V._win = win
  -- keep *same table* for line_map to preserve keymaps; copy values
  for k in pairs(V._line_map) do V._line_map[k] = nil end
  for k, v in pairs(line_map) do V._line_map[k] = v end

  -- Keymaps / Actions (one-time attach)
  local actions = require('org-super-agenda.actions')
  local function reopen(cur) require('org-super-agenda').refresh(cur) end
  actions.set_keymaps(buf, win, V._line_map, reopen)

  -- cursor restore
  if cursor then
    vim.schedule(function()
      pcall(vim.api.nvim_win_set_cursor, win, cursor)
    end)
  end
end

-- public: update existing (no flicker) ---------------------------------------
function V.update(groups, cursor)
  if V.is_open() then
    write_into_existing(V._buf, V._win, groups, cursor)
  else
    V.render(groups, cursor)
  end
end

return V
