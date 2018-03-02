Options:Default "trace"

Tasks:clean()

Tasks:require "main" {
	include = "uk/*.lua",
	exclude = "uk/test*",
	startup = "uk/main.lua",
	output = "build/ukristwallet.lua"
}

Tasks:require "build_tests" {
	include = "uk/*.lua",
	startup = "uk/test.lua",
	output = ".test.lua"
}

Tasks:Task "build" { "clean", "main" } :Description "Main build task"

Tasks:minify "minify" {
	input = "build/ukristwallet.lua",
	output = "build/ukristwallet.min.lua",
}

Tasks:Task "test"({"build_tests"}, function()
  local func = loadfile(shell.resolve(".test.lua"))
	local status, err = pcall(func)
	if status then
		print("Tests completed successfully.")
	else
		error(err)
	end
end)
  :Description "Runs tests."

Tasks:Task "run"({"build"}, function()
  local oldDir = shell.dir()
	shell.setDir(oldDir.."/build")
  shell.run("ukristwallet")
	shell.setDir(oldDir)
end)
  :Description "Runs the program."
