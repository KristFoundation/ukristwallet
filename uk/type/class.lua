local deepcopy = require("uk.type.deepcopy")
local Class_mt = {}

local Class = {
  constructor = function(self, cons)
    self.__cons = cons
    self.mt = deepcopy(Class_mt)
  end,
  extend = function(self, name)
    return setmetatable(self.mt, Class)
  end,
  defaults = function(self, def)
    self.mt.__index = def
  end
}

return Class
