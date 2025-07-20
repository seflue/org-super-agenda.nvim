local cfg = require('org-super-agenda.config').get
local G   = {}

function G.group_items(raw)
  local spec  = cfg().groups

  -- keep groups in the order configured ----------------------------------
  local list = {}
  local map  = {}
  for _, g in ipairs(spec) do
    local entry = { name = g.name, items = {} }
    table.insert(list, entry)
    map[g.name] = entry
  end

  local other
  if cfg().show_other_group then
    other = { name = cfg().other_group_name or 'Other', items = {} }
    table.insert(list, other)
  end

  -- place items into the first matching group ----------------------------
  for _, it in ipairs(raw) do
    local placed = false
    for _, g in ipairs(spec) do
      if g.matcher(it) then
        table.insert(map[g.name].items, it)
        placed = true
        break
      end
    end
    if not placed and other then table.insert(other.items, it) end
  end

  -- optionally drop empties ----------------------------------------------
  if cfg().hide_empty_groups then
    local filtered = {}
    for _, grp in ipairs(list) do
      if #grp.items > 0 then table.insert(filtered, grp) end
    end
    list = filtered
  end

  return list
end

return G

