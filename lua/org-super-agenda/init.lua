-- org-super-agenda.init -------------------------------------------------------
local cfg      = require('org-super-agenda.config')
local source   = require('org-super-agenda.source')
local groups   = require('org-super-agenda.groups')
local view     = require('org-super-agenda.view')

local M        = {}

M._last_opts   = {}
M._last_cursor = nil
M._hidden      = {}
M._undo_stack = {}


function M.push_undo(fn)  M._undo_stack[#M._undo_stack+1] = fn end
function M.pop_undo()
  local f = table.remove(M._undo_stack)
  if f then pcall(f) end
end


local function key_of(it)
  return string.format('%s:%s', it.file or '', it._src_line or 0)
end

-- --- Advanced query helpers --------------------------------------------------
local function parse_query(q)
  if not q or q == '' then return nil end
  local P = {
    inc = {}, exc = {},
    tags_inc = {}, tags_exc = {},
    file_inc = {},
    todo = {},
    prio = { op = nil, val = nil },
    due = nil, sched = nil,
    before = nil, after = nil,
    is_overdue = false, is_done = false,
  }
  q = q:gsub('%s+', ' ')
  for tok in q:gmatch('%S+') do
    local neg = tok:sub(1, 1) == '-'
    local t = neg and tok:sub(2) or tok
    local function splitbar(s)
      local r = {}; for p in s:gmatch('[^|]+') do r[#r + 1] = p end; return r
    end
    if t:match('^tag:') then
      for _, v in ipairs(splitbar(t:sub(5))) do (neg and P.tags_exc or P.tags_inc)[v:lower()] = true end
    elseif t:match('^file:') then
      P.file_inc[#P.file_inc + 1] = t:sub(6):lower()
    elseif t:match('^todo:') then
      for _, v in ipairs(splitbar(t:sub(6))) do P.todo[v] = true end
    elseif t:match('^prio[<>]=?') or t:match('^prio:') then
      local op, val = t:match('^prio([<>]=?)([ABC])')
      if not op then op = ':'; val = t:match('^prio:(%w+)') end
      P.prio = { op = op, val = val }
    elseif t:match('^due[<>=]') then
      local op, n = t:match('^due([<>=]=?)(%-?%d+)'); P.due = { op = op, n = tonumber(n) }
    elseif t:match('^sched[<>=]') or t:match('^sched=') then
      local op, n = t:match('^sched([<>=]=?)(%-?%d+)'); P.sched = { op = op, n = tonumber(n) }
    elseif t:match('^before:') then
      P.before = require('org-super-agenda.date').parse(t:sub(8))
    elseif t:match('^after:') then
      P.after = require('org-super-agenda.date').parse(t:sub(7))
    elseif t == 'is:overdue' then
      P.is_overdue = true
    elseif t == 'is:done' then
      P.is_done = true
    else
      (neg and P.exc or P.inc)[#(neg and P.exc or P.inc) + 1] = t:lower()
    end
  end
  return P
end

local function prio_rank(p) return ({ A = 3, B = 2, C = 1 })[p or ''] or 0 end
local function cmp(num, op, ref)
  if not num or not op or ref == nil then return true end
  if     op == '<'  then return num <  ref
  elseif op == '<=' then return num <= ref
  elseif op == '>'  then return num >  ref
  elseif op == '>=' then return num >= ref
  elseif op == ':'  then return tostring(num) == tostring(ref) -- equality for prio:
  else return num == ref end
end
-- ---------------------------------------------------------------------------

local function build_items(opts)
  local o = opts or {}
  local items = source.collect_items()

  if next(M._hidden) then
    local filtered = {}
    for _, it in ipairs(items) do
      if not M._hidden[key_of(it)] then
        filtered[#filtered + 1] = it
      end
    end
    items = filtered
  end

  if o.todo_filter then
    local wanted = {}
    if type(o.todo_filter) == 'string' then
      wanted[o.todo_filter] = true
    elseif type(o.todo_filter) == 'table' then
      for _, st in ipairs(o.todo_filter) do wanted[st] = true end
    end
    if next(wanted) then
      local filtered = {}
      for _, it in ipairs(items) do
        if wanted[it.todo_state] then table.insert(filtered, it) end
      end
      items = filtered
    end
  end

  if o.headline_filter and o.headline_filter ~= '' then
    local q        = o.headline_filter
    local fuzzy    = o.headline_fuzzy
    local filtered = {}

    local function corpus(it)
      local fn   = vim.fn.fnamemodify(it.file or '', ':t'):gsub('%.org$', '')
      local tags = it.tags and #it.tags > 0 and (':' .. table.concat(it.tags, ':') .. ':') or ''
      return table.concat({
        it.headline or '',
        it.todo_state or '',
        fn,
        tags,
      }, ' '):lower()
    end

    if fuzzy then
      for _, it in ipairs(items) do
        if #vim.fn.matchfuzzy({ corpus(it) }, q) > 0 then
          filtered[#filtered + 1] = it
        end
      end
    else
      q = q:lower()
      for _, it in ipairs(items) do
        if corpus(it):find(q, 1, true) then
          filtered[#filtered + 1] = it
        end
      end
    end
    items = filtered
  end

  -- --- Advanced query (sicher innerhalb von build_items) -------------------
  if o.query and o.query ~= '' then
    local Q = parse_query(o.query)
    if Q then
      local filtered = {}
      for _, it in ipairs(items) do
        local corpus = (function()
          local fn = vim.fn.fnamemodify(it.file or '', ':t'):gsub('%.org$', '')
          local tags = it.tags and #it.tags > 0 and (':' .. table.concat(it.tags, ':') .. ':') or ''
          return table.concat({ it.headline or '', it.todo_state or '', fn, tags }, ' '):lower()
        end)()

        local ok = true
        -- include tokens
        for _, w in ipairs(Q.inc) do if not corpus:find(w, 1, true) then ok=false; break end end
        -- exclude tokens
        if ok then for _, w in ipairs(Q.exc) do if corpus:find(w, 1, true) then ok=false; break end end end
        -- tag filters
        if ok and next(Q.tags_inc) then
          local has=false
          for t,_ in pairs(Q.tags_inc) do
            for _,it_tag in ipairs(it.tags or {}) do if it_tag:lower()==t then has=true end end
          end
          if not has then ok=false end
        end
        if ok and next(Q.tags_exc) then
          for t,_ in pairs(Q.tags_exc) do
            for _,it_tag in ipairs(it.tags or {}) do if it_tag:lower()==t then ok=false end end
          end
        end
        -- file includes (all must match)
        if ok and #Q.file_inc > 0 then
          local fn = vim.fn.fnamemodify(it.file or '', ':t'):lower()
          local hit=true; for _, sub in ipairs(Q.file_inc) do if not fn:find(sub, 1, true) then hit=false; break end end
          if not hit then ok=false end
        end
        -- todo
        if ok and next(Q.todo) and not Q.todo[it.todo_state or ''] then ok=false end
        -- prio
        if ok and Q.prio.op then ok = cmp(prio_rank(it.priority), Q.prio.op, prio_rank(Q.prio.val)) end
        -- due/sched (relativ in Tagen)
        local function days(x) return x and x:days_from_today() or nil end
        if ok and Q.due then
          local d = days(it.deadline); if d == nil or not cmp(d, Q.due.op, Q.due.n) then ok=false end
        end
        if ok and Q.sched then
          local d = days(it.scheduled); if d == nil or not cmp(d, Q.sched.op, Q.sched.n) then ok=false end
        end
        -- absolute before/after
        if ok and Q.before then
          if not it.deadline or not (it.deadline:to_time() < Q.before:to_time()) then ok=false end
        end
        if ok and Q.after then
          if not it.scheduled or not (it.scheduled:to_time() > Q.after:to_time()) then ok=false end
        end
        -- flags
        if ok and Q.is_overdue then
          local over = (it.deadline and it.deadline:is_past()) or (it.scheduled and it.scheduled:is_past())
          if not over then ok=false end
        end
        if ok and Q.is_done and it.todo_state ~= 'DONE' then ok=false end

        if ok then table.insert(filtered, it) end
      end
      items = filtered
    end
  end

  return items
end

local function do_render(cursor_pos, opts, reuse)
  local items   = build_items(opts)
  local grouped = groups.group_items(items)
  local mode    = cfg.get().view_mode or 'classic'
  local data    = grouped

  if reuse and view.is_open() then
    view.update(data, cursor_pos, mode)
  else
    view.render(data, cursor_pos, mode)
  end
end

function M.setup(opts)
  cfg.setup(opts or {})
  vim.api.nvim_create_user_command('OrgSuperAgenda', function() M.open() end, {})
end

--- open a (new) agenda view ---------------------------------------------------
-- normally called by user :OrgSuperAgenda
function M.open(cursor_pos, opts)
  opts           = opts or {}
  M._last_opts   = opts
  M._last_cursor = cursor_pos
  do_render(cursor_pos, opts, false) -- force fresh float
end

--- refresh existing agenda in-place (no flicker) ------------------------------
-- used internally after edits (schedule, deadline, priority...)
function M.refresh(cursor_pos, opts)
  -- merge new opts into stored opts; new opts override
  if opts then
    if opts.todo_filter == nil and M._last_opts then
      M._last_opts.todo_filter = nil
    end
    if opts.headline_filter == nil and M._last_opts then
      M._last_opts.headline_filter = nil
    end
    if opts.headline_fuzzy == nil and M._last_opts then
      M._last_opts.headline_fuzzy = nil
    end
    if opts.query == nil and M._last_opts then
      M._last_opts.query = nil
    end
    M._last_opts = vim.tbl_deep_extend('force', M._last_opts or {}, opts)
  end
  M._last_cursor = cursor_pos or M._last_cursor
  do_render(M._last_cursor, M._last_opts, true)
end

function M.hide_current()
  local lm  = require('org-super-agenda.view').line_map()
  local cur = vim.api.nvim_win_get_cursor(0)
  local it  = lm[cur[1]]
  if not it then return end
  M._hidden[key_of(it)] = true
  M.refresh(cur)
end

function M.reset_hidden()
  M._hidden = {}
end

function M.toggle_duplicates()
  local cur
  if view.is_open() then cur = vim.api.nvim_win_get_cursor(0) end
  cfg.setup({ allow_duplicates = not cfg.get().allow_duplicates })
  if cur then M.refresh(cur) end
end

function M.cycle_view()
  local cur = view.is_open() and vim.api.nvim_win_get_cursor(0) or nil
  local mode = cfg.get().view_mode or 'classic'
  local next_mode = (mode == 'classic') and 'compact' or 'classic'
  cfg.setup({ view_mode = next_mode })
  if cur then M.refresh(cur) else M.open() end
end

function M.on_close()
  if not cfg.get().persist_hidden then
    M.reset_hidden()
  end
end

M._build_items = build_items
return M
