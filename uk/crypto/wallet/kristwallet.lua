local sha256 = require("uk.crypto.sha256")

return function(passphrase)
  return sha256("KRISTWALLET"..passphrase).."-000"
end
