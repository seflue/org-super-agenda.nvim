local U = {}

function U.expand(path) return (path:gsub('^~', vim.fn.expand('$HOME'))) end

-- Directory filter helper ----------------------------------------------------
function U.in_dirs(path, dirlist)
  if #dirlist == 0 then return true end
  for _, d in ipairs(dirlist) do
    if path:find('^' .. vim.pesc(U.expand(d))) then return true end
  end
end

-- ⬇️  NEW: recursively collect *.org files in a directory ---------------------
function U.get_org_files(dir)
  local res, cmd = {}, string.format('find %q -type f -name "*.org"', U.expand(dir))
  local handle = io.popen(cmd)
  if handle then
    for f in handle:lines() do table.insert(res, f) end
    handle:close()
  end
  return res
end

return U
