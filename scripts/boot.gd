extends Node
## Tiny boot scene: hands control to the main menu once the autoloads are up.
##
## Debug launches (arguments after a bare `--`):
##   --night=3     jump straight into a numbered shift
##   --endless     jump into endless round 1

func _ready() -> void:
	await get_tree().process_frame
	UpdateManager.check_for_update()
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--modelcheck"):
			_attach("ModelCheck", "res://scripts/dev/model_check.gd")
			return
	for arg in args:
		if arg.begins_with("--shot"):
			_attach("Screenshot", "res://scripts/dev/screenshot.gd")
			return
	for arg in args:
		if arg.begins_with("--modelshot"):
			_attach("ModelShot", "res://scripts/dev/model_shot.gd")
			return
	var run_soak := "--soak" in args
	if run_soak:
		_attach("Soak", "res://scripts/dev/soak_test.gd")
	if "--chaos" in args:
		_attach("Chaos", "res://scripts/dev/chaos_test.gd")
	if "--inputtest" in args:
		_attach("InputTest", "res://scripts/dev/input_test.gd")
	var run_test := "--selftest" in args
	for arg in args:
		if arg.begins_with("--night="):
			if run_test:
				_attach("SelfTest", "res://scripts/dev/self_test.gd")
			GameManager.start_story_shift(int(arg.get_slice("=", 1)))
			return
		if arg == "--endless":
			if run_test:
				_attach("SelfTest", "res://scripts/dev/self_test.gd")
			GameManager.start_endless(1)
			return
	GameManager.change_scene(GameManager.MENU_SCENE)


func _attach(node_name: String, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var node := Node.new()
	node.name = node_name
	node.set_script(load(path))
	get_tree().root.add_child.call_deferred(node)


func _attach_self_test() -> void:
	_attach("SelfTest", "res://scripts/dev/self_test.gd")

