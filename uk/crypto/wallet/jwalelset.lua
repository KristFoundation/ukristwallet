local sha256 = require("uk.crypto.sha256")
local jwalelset

jwalelset = function(passphrase, i)
  return i == 18 and sha256(passphrase) or jwalelset(sha256(passphrase), (i or 1) + 1)
end

return jwalelset
