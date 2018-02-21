local sha256 = require("uk.crypto.sha256")

return function(username, password)
  return sha256("KRISTWALLETEXTENSION"..sha256(sha256(username).."^"..sha256(password))).."-000"
end
