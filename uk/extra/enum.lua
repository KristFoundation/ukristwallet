return function(vals)
  local tbl = {}

  for k, v in pairs(vals) do
    if type(k) == "number" then
      tbl[v] = k
    else
      tbl[k] = v
    end
  end
  return tbl
end
