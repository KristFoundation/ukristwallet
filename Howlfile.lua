Options:Default "trace"

Tasks:clean()

Tasks:minify "minify" {
	input = "build/ukristwallet.lua",
	output = "build/ukristwallet.min.lua",
}

Tasks:require "main" {
	include = "uk/*.lua",
	startup = "uk/main.lua",
	output = "build/ukristwallet.lua",
	api = true
}

Tasks:Task "build" { "clean", "main", "minify" } :Description "Main build task"

Tasks:Task "run"({"build"}, function()
  shell.run("build/ukristwallet.lua")
end)
  :Description "Runs the program."
