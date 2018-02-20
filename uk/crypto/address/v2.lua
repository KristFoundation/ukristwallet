local sha256 = require("uk.crypto.sha256")
local base36 = require("uk.crypto.base36")

return function(key)
  local protein = {}
  local stick = sha256(sha256(key))
  local n = 0
  local link = 0
  local v2 = "k"
  repeat
    if n < 9 then protein[n] = string.sub(stick,0,2)
    stick = sha256(sha256(stick)) end
    n = n + 1
  until n == 9
  n = 0
  repeat
    link = tonumber(string.sub(stick,1+(2*n),2+(2*n)),16) % 9
    if string.len(protein[link]) ~= 0 then
      v2 = v2 .. base36(tonumber(protein[link],16))
      protein[link] = ''
      n = n + 1
    else
      stick = sha256(stick)
    end
  until n == 9
  return v2
end
