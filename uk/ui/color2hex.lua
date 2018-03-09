local lookup = {
    [colors.white]	= "0",
    [colors.orange]	= "1",
    [colors.magenta]	= "2",
    [colors.lightBlue]	= "3",
    [colors.yellow]	= "4",
    [colors.lime]	= "5",
    [colors.pink]	= "6",
    [colors.gray]	= "7",
    [colors.lightGray]	= "8",
    [colors.cyan]	= "9",
    [colors.purple]	= "a",
    [colors.blue]	= "b",
    [colors.brown]	= "c",
    [colors.green]	= "d",
    [colors.red]	= "e",
    [colors.black]	= "f"
}

return setmetatable(lookup, {
  __call = function(self, color)
    return self[color]
  end
})
