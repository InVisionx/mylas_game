extends Node
## Tiny boot scene: hands control to the main menu once the autoloads are up.
##
## Debug launches (arguments after a bare `--`):
##   --night=3     jump straight into a numbered shift
##   --endless     jump into endless round 1

func _ready() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var run_test := "--selftest" in args
	for arg in args:
		if arg.begins_with("--night="):
			if run_test:
				_attach_self_test()
			GameManager.start_story_shift(int(arg.get_slice("=", 1)))
			return
		if arg == "--endless":
			if run_test:
				_attach_self_test()
			GameManager.start_endless(1)
			return
	GameManager.change_scene(GameManager.MENU_SCENE)


func _attach_self_test() -> void:
	var path := "res://scripts/dev/self_test.gd"
	if not ResourceLoader.exists(path):
		return
	var test := Node.new()
	test.name = "SelfTest"
	test.set_script(load(path))
	get_tree().root.add_child.call_deferred(test)
