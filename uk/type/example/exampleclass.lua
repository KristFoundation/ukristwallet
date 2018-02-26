local example = require("uk.type.class")("ExampleClass")
  :include(require("uk.type.example.examplemixinone"))
  :include(require("uk.type.example.examplemixintwo"))

example.static.static_value = "This is a static value."

function example:initialize(cons_value)
  self.cons_value = cons_value or "No value was passed to the constructor."
end

function example:print()
  print("static_value: "..self.class.static_value)
  print("cons_value: "..self.cons_value)
end

return example
