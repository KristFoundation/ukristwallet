local tests = {
  require("uk.test.class.classtest")
}

for i, test in pairs(tests) do
  print("Running test '"..test.name.."'...")
  local status, err = pcall(test.run)
  if status then
    print("Test '"..test.name.."' completed successfully!")
  else
    error("Error running test '"..test.name.."' "..(err or "<no err>"))
  end
end
