extends Node
## Dev-only: capture what the game actually looks like, so a text-only agent can
## review renders instead of guessing.
##
##   godot --path . -- --night=1 --shot=C:/Users/mattm/Desktop/shots
##
## Runs windowed (screenshots need a real rendering context, --headless cannot).

var _dir := "user://shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_dir = arg.get_slice("=", 1)
	if not _dir.is_absolute_path():
		_dir = ProjectSettings.globalize_path(_dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	process_mode = Node.PROCESS_MODE_ALWAYS

	# Give the shift time to start and a customer to walk in.
	await _wait(3.0)
	var shift := get_tree().get_first_node_in_group("shift_manager")
	if shift != null and shift.has_method("_spawn_customer"):
		shift.call("_spawn_customer")
		await _wait(2.5)
	await _capture("01_wide")

	var customer := _nearest_customer()
	if customer == null:
		await _wait(4.0)
		customer = _nearest_customer()
	if customer != null:
		await _frame_customer(customer, 2.4, "02_customer")
		await _frame_customer(customer, 1.3, "03_closeup")

	await _capture("04_final")
	print("[SHOT] written to ", _dir)
	get_tree().quit(0)


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds, true).timeout


func _nearest_customer() -> Customer:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var best: Customer = null
	var best_distance := INF
	for node in get_tree().get_nodes_in_group("customers"):
		var customer := node as Customer
		if customer == null or not is_instance_valid(customer):
			continue
		var distance := 0.0
		if player != null:
			distance = player.global_position.distance_to(customer.global_position)
		if distance < best_distance:
			best_distance = distance
			best = customer
	return best


## Stand the player in front of a customer and look at them, then capture.
func _frame_customer(customer: Customer, distance: float, name: String) -> void:
	var player := get_tree().get_first_node_in_group("player") as Node3D
	if player == null:
		return
	var look_at_point: Vector3 = customer.global_position + Vector3(0.0, 1.25, 0.0)
	if customer.body != null and customer.body.head != null:
		look_at_point = customer.body.head.global_position
	# Approach from whichever side the customer faces so the front is visible.
	var customer_forward := -customer.global_transform.basis.z
	var spot := customer.global_position + customer_forward * distance
	if player.has_method("teleport"):
		player.call("teleport", spot, look_at_point)
	else:
		player.global_position = spot + Vector3(0.0, 1.0, 0.0)
	await _wait(0.5)
	await _capture(name)


func _capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		print("[SHOT] empty capture for ", name)
		return
	var path := _dir.path_join(name + ".png")
	var error := image.save_png(path)
	print("[SHOT] ", path, " ", image.get_width(), "x", image.get_height(), " err=", error)
