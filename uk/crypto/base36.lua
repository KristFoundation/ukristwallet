return function(byte)
  local byte = 48 + math.floor(byte / 7)
  return string.char(byte + 39 > 122 and 101 or byte > 57 and byte + 39 or byte)
end
