local exc = require("uk.type.example.exampleclass")

local ex1 = exc:new()
local ex2 = exc:new("This is a new cons_value.")

return function()
  ex1:print()
  ex1:mixinone()
  ex1:mixintwo()
  ex2.cons_value = "Test"

  ex2:print()
  ex2:mixinone()
  ex2:mixintwo()

  ex1:print()
end
