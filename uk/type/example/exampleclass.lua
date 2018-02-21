local example = require("uk.type.class"):new("ExampleClass")
  :include(require("uk.type.example.examplemixinone"))
  :include(require("uk.type.example.examplemixintwo"))
  :defaults {
    default_value = "Hello, world!",
    cons_value = "No value was passed to the constructor."
  }

function example:init(cons_value)
  self.cons_value = cons_value
end

function example:print()
  print("default_value: "..self.default_value)
  print("cons_value: "..self.cons_value)
end

return example
