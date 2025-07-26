local utils   = require('org-super-agenda.utils')
local hi      = require('org-super-agenda.highlight')
local get_cfg = require('org-super-agenda.config').get
local L       = {}

-- existing classic builder renamed ------------------------------------------
local function classic_prefix(it, cfg)
  local indent = string.rep(' ', it.level)
  local pri    = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
  local parts  = {
    filename = (cfg.show_filename and it.file) and vim.fn.fnamemodify(it.file, ':t'):gsub('%.org$', ''),
    todo     = it.todo_state,
    priority = pri,
    headline = utils.truncate(it.headline, cfg.heading_max_length),
  }
  local order  = vim.deepcopy(cfg.classic.heading_order or { 'filename', 'todo', 'priority', 'headline' })
  local tok    = {}

  if parts.filename and order[1] == 'filename' then
    table.insert(tok, '[' .. parts.filename .. ']'); table.remove(order, 1)
  end
  for _, k in ipairs(order) do if parts[k] and parts[k] ~= '' then table.insert(tok, parts[k]) end end
  return indent .. table.concat(tok, ' ')
end

-- public --------------------------------------------------------------------
function L.build_classic(groups, win_width)
  local cfg       = get_cfg()
  local rows, hls = {}, {}
  local line_map  = {}
  local widest    = 0
  for _, g in ipairs(groups) do
    for _, it in ipairs(g.items) do
      widest = math.max(widest, #classic_prefix(it, cfg))
    end
  end
  widest = widest + 1

  local ln = 0
  local function emit(s)
    ln = ln + 1; rows[ln] = s; return ln
  end

  for _, grp in ipairs(groups) do
    if #grp.items > 0 then
      emit('')
      local hdln = emit(string.format(cfg.group_format or '* %s', grp.name))
      hls[#hls + 1] = { hdln - 1, 0, -1, 'OrgSA_Group' }

      for _, it in ipairs(grp.items) do
        local indent      = string.rep(' ', it.level)
        local pri         = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil

        local sched_label = cfg.classic.short_date_labels and 'S' or 'SCHEDULED'
        local dead_label  = cfg.classic.short_date_labels and 'D' or 'DEADLINE'
        local meta        = {}
        if it.scheduled then meta[#meta + 1] = sched_label .. ': <' .. tostring(it.scheduled) .. '>' end
        if it.deadline then meta[#meta + 1] = dead_label .. ':  <' .. tostring(it.deadline) .. '>' end
        local meta_str = table.concat(meta, ' ')

        -- Prefix + Highlight‑Spans --------------------------------------
        local parts    = {
          filename = (cfg.show_filename and it.file) and vim.fn.fnamemodify(it.file, ':t'):gsub('%.org$', ''),
          todo     = it.todo_state,
          priority = pri,
          headline = utils.truncate(it.headline, cfg.heading_max_length),
        }
        local order    = vim.deepcopy(cfg.classic.heading_order or { 'filename', 'todo', 'priority', 'headline' })
        local col      = #indent
        local spans    = {}
        local text     = indent

        local function push(field, txt)
          if not txt or txt == '' then return end
          if #text > 0 and text:sub(-1) ~= ' ' then text, col = text .. ' ', col + 1 end
          local s = col
          text, col = text .. txt, col + #txt
          spans[#spans + 1] = { field = field, s = s, e = col }
        end

        if parts.filename and order[1] == 'filename' then
          push('filename', '[' .. parts.filename .. ']'); table.remove(order, 1)
        end
        for _, k in ipairs(order) do push(k, parts[k]) end

        if cfg.classic.inline_dates and meta_str ~= '' then
          if #text < widest then
            text, col = text .. string.rep(' ', widest - #text), widest
          else
            text, col = text .. ' ', col + 1
          end
          local ms = col
          text, col = text .. meta_str, col + #meta_str
          spans[#spans + 1] = { field = 'date', s = ms, e = col }
        end

        if cfg.show_tags and it.tags and #it.tags > 0 then
          local tag   = ':' .. table.concat(it.tags, ':') .. ':'
          local start = win_width - #tag - 1
          if #text + 1 < start then
            text = text .. string.rep(' ', start - #text) .. tag
          else
            text = text .. ' ' .. tag
          end
          spans[#spans + 1] = { field = 'tags', s = #text - #tag, e = #text }
        end

        local lnum = emit(text)
        line_map[lnum] = it

        local hl_cfg = hi.group(it.todo_state)
        for _, sp in ipairs(spans) do
          if hi.want(it.todo_state, sp.field) then
            hls[#hls + 1] = { lnum - 1, sp.s, sp.e, hl_cfg }
          end
        end

        if not cfg.classic.inline_dates and meta_str ~= '' then
          local mln = emit(indent .. '  ' .. meta_str)
          if hi.want(it.todo_state, 'date') then
            hls[#hls + 1] = { mln - 1, #indent + 2, -1, hl_cfg }
          end
        end
      end
    end
  end
  return rows, hls, line_map
end

local function build_labels(it)
  local labels = {}
  if it.deadline then
    local d = it.deadline:days_from_today()
    local lab = (d < 0) and string.format('%d d. ago:', math.abs(d))
        or (d == 0) and 'today:'
        or string.format('in %d d.:', d)
    table.insert(labels, { sev = (d < 0) and 1000 + math.abs(d) or 500 - d, txt = lab })
  end
  if it.scheduled then
    local d = it.scheduled:days_from_today()
    local lab = (d < 0) and string.format('Sched. %dx:', math.abs(d))
        or (d == 0) and 'Sched. today:'
        or string.format('Sched. in %d d.:', d)
    table.insert(labels, { sev = (d < 0) and 900 + math.abs(d) or 400 - d, txt = lab })
  end
  table.sort(labels, function(a, b) return a.sev > b.sev end)
  local parts = {}
  for _, l in ipairs(labels) do table.insert(parts, l.txt) end
  return table.concat(parts, '  ')
end

function L.build_compact(groups, win_width)
  local cfg = get_cfg()
  if groups and #groups > 0 and groups[1].items == nil then
    groups = { { name = cfg.other_group_name or 'Other', items = groups } }
  end
  local rows, hls = {}, {}
  local line_map  = {}

  local fname_w   = cfg.compact and cfg.compact.filename_min_width or 8
  local label_w   = cfg.compact and cfg.compact.label_min_width or 12

  for _, grp in ipairs(groups) do
    for _, it in ipairs(grp.items) do
      local name = vim.fn.fnamemodify(it.file or '', ':t'):gsub('%.org$', '') .. ':'
      if #name > fname_w then fname_w = #name end
    end
  end

  local ln = 0
  local function emit(s)
    ln = ln + 1; rows[ln] = s; return ln
  end

  for _, grp in ipairs(groups) do
    if #grp.items > 0 then
      emit('')
      local hdln = emit(string.format(cfg.group_format or '* %s', grp.name))
      hls[#hls + 1] = { hdln - 1, 0, -1, 'OrgSA_Group' }

      for _, it in ipairs(grp.items) do
        local name  = (vim.fn.fnamemodify(it.file or '', ':t'):gsub('%.org$', '') .. ':')
        local label = build_labels(it)
        if label == '' then label = string.rep(' ', label_w) else label = string.format('%-' .. label_w .. 's', label) end
        local pri   = (it.priority and it.priority ~= '') and ('[#' .. it.priority .. ']') or nil
        local todo  = it.todo_state or ''
        local head  = utils.truncate(it.headline or '', cfg.heading_max_length)

        local text  = ''
        local spans = {}
        -- filename col
        local s_fn  = #text
        text        = text .. string.format('%-' .. fname_w .. 's', name)
        table.insert(spans, { field = 'filename', s = s_fn, e = #text })
        -- label col
        local s_lab = #text
        text = text .. label
        table.insert(spans, { field = 'date', s = s_lab, e = #text })
        -- space
        text = text .. ' '
        -- todo / pri / head
        local s_todo = #text
        text = text .. todo; table.insert(spans, { field = 'todo', s = s_todo, e = #text })
        if pri then
          text = text .. ' '; local s_pr = #text; text = text .. pri; table.insert(spans,
            { field = 'priority', s = s_pr, e = #text })
        end
        text = text .. ' '
        local s_head = #text
        text = text .. head; table.insert(spans, { field = 'headline', s = s_head, e = #text })

        if cfg.show_tags and it.tags and #it.tags > 0 then
          local tag = ':' .. table.concat(it.tags, ':') .. ':'
          local start = win_width - #tag - 1
          if #text + 1 < start then text = text .. string.rep(' ', start - #text) .. tag else text = text .. ' ' .. tag end
          table.insert(spans, { field = 'tags', s = #text - #tag, e = #text })
        end

        local lnum = emit(text); line_map[lnum] = it
        local hl_cfg = hi.group(it.todo_state)
        for _, sp in ipairs(spans) do
          if hi.want(it.todo_state, sp.field) then
            hls[#hls + 1] = { lnum - 1, sp.s, sp.e,
              hl_cfg }
          end
        end
      end
    end
  end
  return rows, hls, line_map
end

return L
