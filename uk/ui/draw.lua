local c2h = require("uk.ui.color2hex")

local draw = require("uk.type.class")("Draw")
  :include(require("uk.ui.renderable"))

function draw:initialize(w, h, fg, bg)
  self.width = w
  self.height = h
  self.foreground = c2h(fg)
  self.background = c2h(bg)
  self._tbuf = {}
  self._fbuf = {}
  self._bbuf = {}
  self:clear(self.foreground, self.background)
end

function draw:transformpos(x, y)
  return self.width * (y - 1) + x
end

function draw:clear(fg, bg)
  for i = 1, self.height * self.width do
    self._tbuf[i] = " "
    self._fbuf[i] = self.foreground
    self._bbuf[i] = self.background
  end
end

function draw:getpixel(x, y)
  local pos = self:transformpos(x, y)

  return self._tbuf[pos], self._fbuf[pos], self._bbuf[pos]
end

function draw:pixel(x, y, t, f, b)
  local pos = self:transformpos(x, y)
  if t then
    self._tbuf[pos] = t
  end

  if f then
    self._fbuf[pos] = f
  end

  if b then
    self._bbuf[pos] = b
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
  for i = 0, l do
    self:pixel(x + i, y, nil, nil, c2h(c))
  end
end

function draw:vline(x, y, l, c)
  for i = 0, l do
    self:pixel(x, y + i, nil, nil, c2h(c))
  end
end

function draw:draw(draw, xo, yo)
  for y = 1, draw.height do
    for x = 1, draw.width do
      self:pixel(x + xo, y + yo, draw:getpixel(x, y))
    end
  end
end

function draw:_render()
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
