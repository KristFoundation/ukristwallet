local c2h = require("uk.ui.color2hex")

local draw = require("uk.type.class")("Draw")
  :include(require("uk.ui.renderable"))

function draw:initialize(w, h, fg, bg)
  self.width = w
  self.height = h
  self.foreground = type(fg) == "number" and c2h(fg) or fg or " "
  self.background = type(bg) == "number" and c2h(bg) or bg or " "
  self._tbuf = {}
  self._fbuf = {}
  self._bbuf = {}
  self.children = {}
  self:clear(self.foreground, self.background)
end

function draw:transformpos(x, y)
  if x > self.width then
    error("X out of bounds: "..x.."/"..self.width)
  elseif y > self.height then
    error("Y out of bounds: "..y.."/"..self.height)
  end
  return self.width * (y - 1) + x
end

function draw:clear(fg, bg)
  fg = type(fg) == "number" and c2h(fg) or fg or self.foreground
  bg = type(bg) == "number" and c2h(bg) or bg or self.background

  for i = 1, self.height * self.width do
    self._tbuf[i] = " "
    self._fbuf[i] = fg
    self._bbuf[i] = bg
  end
end

function draw:getpixel(x, y)
  local pos = self:transformpos(x, y)

  return self._tbuf[pos], self._fbuf[pos], self._bbuf[pos]
end

function draw:pixel(x, y, t, f, b)
  t = t and t:sub(1,1) or nil
  fg = f and (type(f) == "number" and c2h(f) or f) or self.foreground
  bg = b and (type(b) == "number" and c2h(b) or b) or self.background

  local pos = self:transformpos(x, y)

  if t and t ~= " " then
    self._tbuf[pos] = t
  end

  if fg and f ~= " " then
    self._fbuf[pos] = fg
  end

  if bg and b ~= " " then
    self._bbuf[pos] = bg
  end
end

function draw:text(text, x, y, fg, bg)
  if type(text) ~= "string" then
    text = tostring(text)
  end

  for i = 1, text:len() do
    local char = text:sub(i, i)
    if char ~= "\n" then
      self:pixel(x + i - 1, y, char, fg, bg)
    else
      y = y + 1
    end
  end
end

function draw:box(x, y, x2, y2, c)
  local w, h = x2 - x, y2 - y

  self:hline(x, y, w, c)
  self:hline(x, y + h, w, c)
  self:vline(x, y, w, c)
  self:vline(x + h, y, w, c)
end

function draw:hline(x, y, l, c)
  for i = 1, l do
    self:pixel(x + i - 1, y, nil, nil, c2h(c))
  end
end

function draw:vline(x, y, l, c)
  for i = 0, l do
    self:pixel(x, y + i, nil, nil, c2h(c))
  end
end

function draw:draw(d, xo, yo)
  assert(type(d.height) == "number", "Height must be number")
  assert(type(d.width) == "number", "Width must be number")
  for y = 1, d.height do
    for x = 1, d.width do
      self:pixel(x + xo - 1, y + yo - 1, d:getpixel(x, y))
    end
  end
end

function draw:child(draw, xo, yo)
  table.insert(self.children, {
    x = xo,
    y = yo,
    draw = draw
  })
end

function draw:_render()
  for k, v in pairs(self.children) do
    self:draw(v.draw, v.x, v.y)
  end
  local t, f, b = {}, {}, {}

  for y = 1, self.height do
    t[y] = ""
    f[y] = ""
    b[y] = ""

    for x = 1, self.width do
      t[y] = t[y]..self._tbuf[self:transformpos(x, y)]
      f[y] = f[y]..self._fbuf[self:transformpos(x, y)]
      b[y] = b[y]..self._bbuf[self:transformpos(x, y)]
    end
  end

  return t, f, b
end

return draw
