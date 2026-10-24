extends Node
## Dev-only: render a customer body in isolation from a few angles so the model
## itself can be reviewed (scale, facing, feet on the ground, pose).
##
##   godot --path . -- --modelshot=C:/Users/mattm/Desktop/shots
##
## Windowed only: --headless cannot render.

var _dir := "user://shots"
var _camera: Camera3D
var _body: CustomerBody
var _model := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--modelshot="):
			_dir = arg.get_slice("=", 1)
		elif arg.begins_with("--model="):
			_model = arg.get_slice("=", 1)
	if not _dir.is_absolute_path():
		_dir = ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS

	_build_stage()
	_body = CustomerBody.new()
	_body.name = "Subject"
	if not _model.is_empty():
		_body.model_override = _model
	add_child(_body)
	_body.build(7, {})

	await _wait(0.4)
	print("[MODELSHOT] using_model=", _body.using_model, " path=", _body.model_path)
	var meshes := _body.find_children("*", "MeshInstance3D", true, false)
	print("[MODELSHOT] mesh_count=", meshes.size())
	for node in meshes:
		var instance := node as MeshInstance3D
		print("[MODELSHOT]  ", instance.name, " aabb=", instance.get_aabb(),
			" surfaces=", instance.mesh.get_surface_count() if instance.mesh else 0)
	if meshes.size() > 0:
		var world_box: AABB = (meshes[0] as MeshInstance3D).global_transform * (meshes[0] as MeshInstance3D).get_aabb()
		print("[MODELSHOT] subject world aabb=", world_box, " height=", snappedf(world_box.size.y, 0.01))
	# Idle pose first, then a mid-stride frame from the walk cycle.
	_body.animate(0.0, 0.0, Vector3.ZERO)
	await _wait(0.6)
	for index in 3:
		await _capture_from(index * 45.0, "model_idle_%02d" % index)
	await _capture_portrait("model_portrait")
	_body.animate(0.0, 1.25, Vector3.ZERO)
	await _wait(0.55)
	await _capture_from(35.0, "model_walk")
	print("[MODELSHOT] written to ", _dir)
	get_tree().quit(0)


func _build_stage() -> void:
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.0, 0.0, 0.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.6, 0.62, 0.7)
	environment.ambient_light_energy = 0.9
	world.environment = environment
	add_child(world)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 35.0, 0.0)
	sun.light_energy = 1.6
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, -140.0, 0.0)
	fill.light_energy = 0.5
	add_child(fill)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.13, 0.14, 0.16)
	ground.material_override = material
	ground.visible = "--noground" not in OS.get_cmdline_user_args()
	add_child(ground)

	_camera = Camera3D.new()
	_camera.fov = 50.0
	add_child(_camera)
	_camera.current = true


func _capture_from(degrees: float, name: String) -> void:
	var radians := deg_to_rad(degrees)
	_camera.fov = 48.0
	_camera.position = Vector3(sin(radians) * 2.05, 1.05, cos(radians) * 2.05)
	_camera.look_at(Vector3(0.0, 0.95, 0.0))
	await _wait(0.25)
	print("[MODELSHOT] state ", name, " cam=", _camera.position,
		" model_scale=", _body._model_root.scale if _body._model_root else "none",
		" clip=", _body._anim.current_animation if _body._anim else "none",
		" speed=", _body._anim.speed_scale if _body._anim else 0.0,
		" pos=", _body._model_root.position if _body._model_root else Vector3.ZERO)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		print("[MODELSHOT] empty ", name)
		return
	var path := _dir.path_join(name + ".png")
	print("[MODELSHOT] ", path, " ", image.get_width(), "x", image.get_height(),
		" err=", image.save_png(path))


## Head-and-shoulders framing: the only way a small vision model can judge a face.
func _capture_portrait(name: String) -> void:
	_camera.fov = 32.0
	_camera.position = Vector3(0.45, 1.62, 1.05)
	_camera.look_at(Vector3(0.0, 1.55, 0.0))
	await _wait(0.25)
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		print("[MODELSHOT] empty ", name)
		return
	var path := _dir.path_join(name + ".png")
	print("[MODELSHOT] ", path, " ", image.get_width(), "x", image.get_height(),
		" err=", image.save_png(path))


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout
