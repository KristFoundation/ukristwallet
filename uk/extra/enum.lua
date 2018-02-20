return function(vals)
  local tbl = {}
  tbl.lookup = {}

  for k, v in pairs(vals) do
    if type(k) == "number" then
      tbl[v] = k
      tbl.lookup[k] = v
    else
      tbl[k] = v
      tbl.loopup[v] = k
    end
  end
  return tbl
end
