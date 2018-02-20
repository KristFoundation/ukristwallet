Options:Default "trace"

Tasks:clean()

Tasks:require "main" {
	include = "uk/*.lua",
	startup = "uk/main.lua",
	output = "build/ukristwallet.lua",
	api = true
}

Tasks:Task "build" { "clean", "main" } :Description "Main build task"

Tasks:minify "minify" {
	input = "build/ukristwallet.lua",
	output = "build/ukristwallet.min.lua",
}

Tasks:Task "run"({"build"}, function()
  local oldDir = shell.dir()
	shell.setDir(oldDir.."/build")
  shell.run("ukristwallet")
	shell.setDir(oldDir)
end)
  :Description "Runs the program."
