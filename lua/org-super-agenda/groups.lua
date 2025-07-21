local cfg = require('org-super-agenda.config').get
local G   = {}

local function is_done_and_past(it)
  if it.todo_state ~= 'DONE' then
    return false
  end
  local past_deadline  = (not it.deadline) or it.deadline:is_past()
  local past_scheduled = (not it.scheduled) or it.scheduled:is_past()
  return past_deadline and past_scheduled
end

-------------------------------------------------------------------------------
-- Gruppierung ----------------------------------------------------------------
-------------------------------------------------------------------------------
function G.group_items(raw)
  local spec = cfg().groups

  local list, map = {}, {}
  for _, g in ipairs(spec) do
    local entry = { name = g.name, items = {} }
    table.insert(list, entry)
    map[g.name] = entry
  end

  -- Catch‑All "Other" -----------------------------------------------------
  local other
  if cfg().show_other_group then
    other = { name = cfg().other_group_name, items = {} }
    table.insert(list, other)
  end

  for _, it in ipairs(raw) do
    local placed = false
    -- explizite Gruppen
    for _, g in ipairs(spec) do
      if g.matcher(it) then
        table.insert(map[g.name].items, it)
        placed = true
        break
      end
    end
    if not placed and other and not is_done_and_past(it) then
      table.insert(other.items, it)
    end
  end

  if cfg().hide_empty_groups then
    local filtered = {}
    for _, grp in ipairs(list) do
      if #grp.items > 0 then
        table.insert(filtered, grp)
      end
    end
    list = filtered
  end

  return list
end

return G
