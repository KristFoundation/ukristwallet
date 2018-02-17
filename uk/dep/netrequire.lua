local consts = require("uk.extra.consts")

return function(url)
  local cleaned_url = url:gsub("[^%a]","")
  local path = fs.combine(consts.DATA_DIR, cleaned_url)

  if not fs.exists(consts.DATA_DIR) then
  end

  if not fs.exists(path) then
    local req = http.get(url)
    local fi = fs.open(path, "w")
    fi.write(req.readAll())
    fi.close()
    --req.close()
    print(path)
    return dofile(path)
  else
    return dofile(path)
  end
end
