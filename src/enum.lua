local enum = function(...)
  local tbl = {}
  local arg = {...}
  for i, v in pairs(arg) do
    tbl[v] = v
  end
  return tbl
end
