local exc = require("uk.type.example.exampleclass")

local ex1 = exc()
local ex2 = exc("This is a new cons_value.")

return function()
  print("Class 1:")
  print(tostring(ex1))
  ex1:print()
  ex1:mixinone()
  ex1:mixintwo()

  print("Class 2:")
  print(tostring(ex2))
  ex2:print()
  ex2:mixinone()
  ex2:mixintwo()
end
