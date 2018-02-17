local netrequire = require("uk.dep.netrequire")

return function(user, repo, file, branch)
  return netrequire("https://raw.githubusercontent.com/"..user.."/"..repo.."/"..(branch or "master").."/"..file)
end
