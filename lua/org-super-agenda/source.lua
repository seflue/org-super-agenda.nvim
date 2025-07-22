-- org-super-agenda – headline loader (debug edition) ---------------------------
-- Updated: filter issue fixed; always start from org_api.load() without args.
-------------------------------------------------------------------------------
local utils = require('org-super-agenda.utils')
local cfg   = require('org-super-agenda.config').get
local Date  = require('org-super-agenda.date')
local Item  = require('org-super-agenda.org_item')

local S     = {}

DEBUG       = false
local function log(msg)
  if not DEBUG then return end
  print('[OSA:source] ' .. msg)
end

-------------------------------------------------------------------------------
-- Helper: obtain OrgApiFile list from nvim‑orgmode ---------------------------
-------------------------------------------------------------------------------
local function load_org_files()
  ---------------------------------------------------------------------------
  -- 0.  Lookup‑Tabelle aller vom User gewünschten Org‑Dateien -------------
  ---------------------------------------------------------------------------
  local wanted = {}
  for _, f in ipairs(cfg().org_files) do wanted[utils.expand(f)] = true end
  for _, d in ipairs(cfg().org_directories) do
    for _, f in ipairs(utils.get_org_files(d)) do wanted[f] = true end
  end

  ---------------------------------------------------------------------------
  -- 1.  Geladene, aber **unveränderte** Buffer wegwerfen ------------------
  ---------------------------------------------------------------------------
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= '' and wanted[name]
        and vim.api.nvim_buf_is_loaded(bufnr)
        and not vim.api.nvim_buf_get_option(bufnr, 'modified') then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  ---------------------------------------------------------------------------
  -- 2.  Org‑Mode‑Datenbasis auffrischen -----------------------------------
  ---------------------------------------------------------------------------
  local ok_org, org = pcall(require, 'orgmode')
  if ok_org and org and type(org.reload) == 'function' then
    pcall(function() org:reload() end)
  end

  local ok_api, api_root = pcall(require, 'orgmode.api')
  if not ok_api or type(api_root) ~= 'table' then return {} end
  local org_api = api_root.load and api_root or api_root.org
  if not (org_api and org_api.load) then return {} end

  ---------------------------------------------------------------------------
  -- 3.  Dateien laden, ggf. filtern → Liste `files` -----------------------
  ---------------------------------------------------------------------------
  local loaded_raw = org_api.load() -- map | list | single
  local files      = {}

  if loaded_raw then
    if loaded_raw.filename or loaded_raw._file then
      files = { loaded_raw }
    elseif vim.islist(loaded_raw) then
      files = loaded_raw
    else
      for _, f in pairs(loaded_raw) do files[#files + 1] = f end
    end
  end

  if next(wanted) then
    local filtered = {}
    for _, f in ipairs(files) do
      if wanted[f.filename] then filtered[#filtered + 1] = f end
    end
    files = filtered
  end

  ---------------------------------------------------------------------------
  -- 4.  Inhalt jedes Files wirklich **neu** parsen ------------------------
  ---------------------------------------------------------------------------
  for i, f in ipairs(files) do files[i] = f:reload() end
  return files
end

-------------------------------------------------------------------------------
-- Headline → Item -----------------------------------------------------------
local function headline_to_item(h)
  return Item.new {
    headline   = h.title,
    level      = h.level,
    tags       = h.tags or {},
    priority   = h.priority,
    todo_state = h.todo_value,
    scheduled  = Date.from_orgdate(h.scheduled),
    deadline   = Date.from_orgdate(h.deadline),
    properties = h.properties or {},
    file       = h.file.filename,
    _src_line  = h.position and h.position.start_line, -- 1‑based, matches API
  }
end

-------------------------------------------------------------------------------
-- Public API ----------------------------------------------------------------
-------------------------------------------------------------------------------
function S.collect_items()
  local items = {}

  local function walk(hl)
    table.insert(items, headline_to_item(hl))
    for _, c in ipairs(hl.headlines or {}) do walk(c) end
  end

  local files = load_org_files()
  log('iterating ' .. #files .. ' files for headlines')
  for _, file in ipairs(files) do
    for _, hl in ipairs(file.headlines or {}) do walk(hl) end
  end
  log('final headline count = ' .. #items)
  -- deduplicate by file + line -------------------------------------------
  local seen, uniq = {}, {}
  for _, it in ipairs(items) do
    local key = string.format('%s:%s', it.file or '', it._src_line or 0)
    if not seen[key] then
      seen[key] = true
      table.insert(uniq, it)
    end
  end
  ---------------------------------------------------------------------------
  -- drop headlines without a recognized TODO keyword -----------------------
  ---------------------------------------------------------------------------
  local valid = {}
  for _, st in ipairs(cfg().todo_states or {}) do
    if st.name then valid[st.name] = true end
  end
  local filtered = {}
  for _, it in ipairs(uniq) do
    if valid[it.todo_state] then table.insert(filtered, it) end
  end

  return filtered
end

return S
