-- adapters/neovim/source_orgmode.lua -- implements SourcePort
local utils = require('org-super-agenda.adapters.neovim.utils')
local cfg   = require('org-super-agenda.config').get
local Date  = require('org-super-agenda.core.date')
local Item  = require('org-super-agenda.core.item')

local S = {}

local function load_org_files()
  local C = cfg()
  local want, skip = {}, {}
  local function add(tbl, k) if k and k ~= '' then tbl[utils.expand(k)] = true end end

  for _, f in ipairs(C.org_files or {}) do add(want, f) end
  for _, d in ipairs(C.org_directories or {}) do
    for _, f in ipairs(utils.get_org_files(d)) do add(want, f) end
  end
  for _, f in ipairs(C.exclude_files or {}) do add(skip, f) end
  for _, d in ipairs(C.exclude_directories or {}) do
    for p in pairs(want) do
      if p:find('^' .. vim.pesc(utils.expand(d))) then skip[p] = true end
    end
  end

  -- force reload of clean loaded buffers so orgmode re-parses
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if want[name] and not skip[name]
       and vim.api.nvim_buf_is_loaded(bufnr)
       and not vim.api.nvim_buf_get_option(bufnr, 'modified') then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  local ok_api, api_root = pcall(require, 'orgmode.api'); if not ok_api then return {} end
  local org_api = api_root.load and api_root or api_root.org
  if not (org_api and org_api.load) then return {} end

  local files = {}
  for path in pairs(want) do
    if not skip[path] then
      local ok, f = pcall(org_api.load, path)
      if ok and f then
        if f.filename or f._file then files[#files+1] = f
        elseif vim.islist(f) then vim.list_extend(files, f) end
      end
    end
  end
  for i,f in ipairs(files) do files[i] = f:reload() end
  return files
end

local function headline_to_item(h)
  return Item.new {
    headline   = h.title,
    level      = h.level,
    tags       = h.tags or {},
    priority   = h.priority,
    todo_state = h.todo_value,         -- may be nil/'' for events
    scheduled  = Date.from_orgdate(h.scheduled),
    deadline   = Date.from_orgdate(h.deadline),
    properties = h.properties or {},
    file       = h.file and h.file.filename or h.filename,
    _src_line  = h.position and h.position.start_line,
  }
end

function S.collect()
  local items = {}
  local function walk(hl)
    items[#items+1] = headline_to_item(hl)
    for _, c in ipairs(hl.headlines or {}) do walk(c) end
  end

  local files = load_org_files()
  for _, file in ipairs(files) do
    for _, hl in ipairs(file.headlines or {}) do walk(hl) end
  end

  -- dedupe by file:line
  local seen, uniq = {}, {}
  for _, it in ipairs(items) do
    local key = string.format('%s:%s', it.file or '', it._src_line or 0)
    if not seen[key] then seen[key]=true; uniq[#uniq+1]=it end
  end

  -- keep:
  --  • items with a known TODO state, OR
  --  • items with NO TODO but with a date (scheduled/deadline)  ← events
  local valid = {}
  for _, st in ipairs(cfg().todo_states or {}) do valid[st.name] = true end
  local out = {}
  for _, it in ipairs(uniq) do
    local state = it.todo_state
    if valid[state] then
      out[#out+1] = it
    elseif (state == nil or state == '') and (it.scheduled or it.deadline) then
      out[#out+1] = it
    end
  end
  return out
end

return S

