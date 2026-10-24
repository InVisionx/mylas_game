class_name HorrorDirector
extends Node3D
## Environmental dread and the consequences of letting something leave.

var builder: StoreBuilder
var player: PlayerController
var shift: ShiftManager

var night := 1
var _event_timer := 24.0
var _busy := false
var _last_scare := ""
var _rng := RandomNumberGenerator.new()
var _base_energies: Array = []


func setup(refs: Dictionary) -> void:
	builder = refs.get("builder")
	player = refs.get("player")
	shift = refs.get("shift")
	add_to_group("horror_director")
	_rng.randomize()
	if builder:
		for light in builder.ceiling_lights:
			_base_energies.append(light.light_energy)
	night = int(GameManager.current_shift.get("night_for_horror", GameManager.shift_index))


func _process(delta: float) -> void:
	if not GameManager.shift_active or _busy:
		return
	_event_timer -= delta
	if _event_timer <= 0.0:
		_event_timer = _rng.randf_range(26.0, 46.0)
		_play_random_environmental()


func _play_random_environmental() -> void:
	var pool := GameData.environmental_events_for_night(night)
	if pool.is_empty():
		return
	var total := 0.0
	for event in pool:
		total += float(event.get("weight", 1.0))
	var roll := _rng.randf() * total
	var chosen: Dictionary = pool[0]
	for event in pool:
		roll -= float(event.get("weight", 1.0))
		if roll <= 0.0:
			chosen = event
			break
	_play_environmental(str(chosen.get("id", "")))


func _play_environmental(id: String) -> void:
	match id:
		"lights_flicker":
			_flicker_lights(1.6, 0.55)
			Events.horror_event_started.emit("lights_flicker")
		"fridge_surge":
			AudioManager.play("breaker", -16.0, 0.7)
			for light in builder.spill_lights:
				if light.light_color.b > 0.9:
					_light_pulse(light, 0.4, 2.4)
		"distant_steps":
			_footsteps_sequence(Vector3(_rng.randf_range(-7.0, 7.0), 0.0, _rng.randf_range(-7.0, -2.0)))
		"door_chime":
			AudioManager.play("door_chime", -20.0, 1.02)
			if builder:
				builder.open_entrance(true)
				await get_tree().create_timer(2.2).timeout
				if is_instance_valid(builder):
					builder.open_entrance(false)
		"shelf_product":
			AudioManager.play_at("product_fall", Vector3(_rng.randf_range(-7.0, 7.0), 1.2, _rng.randf_range(-7.0, 1.0)), -12.0, _rng.randf_range(0.9, 1.2))
		"cart_roll":
			AudioManager.play_at("cart", Vector3(_rng.randf_range(-7.0, 7.0), 0.3, -8.0), -14.0, _rng.randf_range(0.9, 1.1))
		"still_customer":
			_freeze_a_customer()
		"camera_figure":
			_spawn_camera_figure()
		"phone_ring":
			AudioManager.play_at("phone", Vector3(-3.2, 1.0, -12.9), -10.0, 1.0)
		"whisper":
			AudioManager.play_at("whisper", player.global_position + Vector3(0, 1.6, 0) if player else Vector3.ZERO, -8.0)
		"power_dip":
			_power_dip()
		"freezer_bang":
			AudioManager.play_at("bang", Vector3(-1.0, 1.0, -7.9), -6.0, 0.9)
			if player:
				player.shake(0.012, 0.4)
		"all_lights_out":
			_all_lights_out(3.4)
		"reflection_double":
			_spawn_watcher()
		"silence":
			AudioManager.loop_set_volume("hum_loop", -60.0, 0.4)
			AudioManager.loop_set_volume("room_loop", -60.0, 0.4)
			await get_tree().create_timer(5.0).timeout
			AudioManager.loop_set_volume("hum_loop", -20.0, 1.5)
			AudioManager.loop_set_volume("room_loop", -22.0, 1.5)
		_:
			pass
	Events.horror_event_finished.emit(id)


func _flicker_lights(duration: float, intensity: float) -> void:
	if _busy:
		return
	_busy = true
	var elapsed := 0.0
	while elapsed < duration:
		var drop := _rng.randf() < intensity
		for light in builder.ceiling_lights:
			light.light_energy = 0.05 if drop else 1.15
			var panel: Node = light.get_meta("panel", null)
			if panel and panel is MeshInstance3D:
				panel.visible = not drop
		AudioManager.play("breaker", -30.0, _rng.randf_range(0.9, 1.2))
		var wait := _rng.randf_range(0.04, 0.16)
		await get_tree().create_timer(wait).timeout
		elapsed += wait
	_restore_lights()
	_busy = false


func _restore_lights() -> void:
	if builder == null:
		return
	for i in builder.ceiling_lights.size():
		var light := builder.ceiling_lights[i]
		light.light_energy = _base_energies[i] if i < _base_energies.size() else 1.15
		var panel: Node = light.get_meta("panel", null)
		if panel and panel is MeshInstance3D:
			panel.visible = true


func _light_pulse(light: OmniLight3D, low: float, duration: float) -> void:
	var start := light.light_energy
	var tween := create_tween()
	tween.tween_property(light, "light_energy", low, duration * 0.25)
	tween.tween_property(light, "light_energy", start, duration * 0.75)


func _footsteps_sequence(origin: Vector3) -> void:
	for i in _rng.randi_range(4, 7):
		AudioManager.play_at("step_%d" % _rng.randi_range(1, 4), origin + Vector3(_rng.randf_range(-0.3, 0.3), 0, i * 0.6), -12.0, _rng.randf_range(0.85, 1.0))
		await get_tree().create_timer(0.42).timeout


func _freeze_a_customer() -> void:
	var candidates: Array = []
	for customer in get_tree().get_nodes_in_group("customers"):
		if customer is Customer and customer.state != Customer.State.AT_COUNTER:
			candidates.append(customer)
	if candidates.is_empty():
		return
	var chosen: Customer = candidates[_rng.randi_range(0, candidates.size() - 1)]
	chosen.body.freeze()
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(chosen):
		chosen.body.unfreeze()


func _spawn_camera_figure() -> void:
	var figure := _make_figure(Vector3(0.5, 2.6, 0.4), true)
	figure.position = Vector3(_rng.randf_range(-6.0, 6.0), 1.3, _rng.randf_range(-7.0, -1.0))
	add_child(figure)
	AudioManager.play("static", -14.0)
	await get_tree().create_timer(2.6).timeout
	if is_instance_valid(figure):
		figure.queue_free()


func _spawn_watcher() -> void:
	var watcher := _make_figure(Vector3(0.5, 2.4, 0.35), false)
	watcher.position = Vector3(_rng.randf_range(-3.0, 3.0), 1.2, -8.0)
	add_child(watcher)
	AudioManager.play_at("whisper", watcher.position, -6.0)
	await get_tree().create_timer(4.0).timeout
	if is_instance_valid(watcher):
		var tween := create_tween()
		tween.tween_property(watcher, "position:y", -2.0, 0.6)
		tween.tween_callback(watcher.queue_free)


func _make_figure(size: Vector3, camera_only: bool) -> MeshInstance3D:
	var figure := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	figure.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.01, 0.01, 0.015)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	figure.material_override = material
	if camera_only:
		figure.layers = 4
	figure.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return figure


func _power_dip() -> void:
	for light in builder.ceiling_lights:
		light.light_energy = 0.02
		var panel: Node = light.get_meta("panel", null)
		if panel and panel is MeshInstance3D:
			panel.visible = false
	AudioManager.play("breaker", -8.0)
	await get_tree().create_timer(1.1).timeout
	_restore_lights()


func _all_lights_out(duration: float) -> void:
	_busy = true
	for light in builder.ceiling_lights:
		light.light_energy = 0.0
		var panel: Node = light.get_meta("panel", null)
		if panel and panel is MeshInstance3D:
			panel.visible = false
	AudioManager.play("breaker", -6.0)
	AudioManager.loop_start("heartbeat", -20.0, "Ambience", 0.4)
	await get_tree().create_timer(duration).timeout
	_restore_lights()
	AudioManager.loop_stop("heartbeat", 1.5)
	_busy = false


# --- Jumpscares -------------------------------------------------------------

func play_entity_departure(customer: Customer) -> void:
	if customer == null or not is_instance_valid(customer) or player == null:
		return
	var kind := _pick_scare()
	GameManager.open_modal()
	player.focus_mode(true)
	Events.jumpscare_started.emit(kind)
	AudioManager.loop_set_volume("hum_loop", -60.0, 0.2)
	AudioManager.loop_set_volume("room_loop", -60.0, 0.2)

	match kind:
		"register":
			await _scare_register(customer)
		"lights":
			await _scare_lights(customer)
		"reflection":
			await _scare_reflection(customer)
		"counter":
			await _scare_counter(customer)
		_:
			await _scare_doorway(customer)

	AudioManager.loop_set_volume("hum_loop", -20.0, 2.0)
	AudioManager.loop_set_volume("room_loop", -22.0, 2.0)
	GameManager.close_modal()
	if is_instance_valid(player):
		player.focus_mode(false)
		player.release_forced_look()
	Events.jumpscare_finished.emit(kind)


func _pick_scare() -> String:
	var pool := GameData.jumpscares_for_night(night)
	var candidates: Array = []
	for scare in pool:
		if str(scare.get("id", "")) != _last_scare:
			candidates.append(scare)
	if candidates.is_empty():
		candidates = pool
	var chosen: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else { "id": "doorway" }
	_last_scare = str(chosen.get("id", "doorway"))
	return _last_scare


func _scare_doorway(customer: Customer) -> void:
	customer.path = [Vector3(0.0, 0.0, 10.6)]
	customer.path_index = 0
	customer.set_state(Customer.State.WALKING)
	await customer.navigation_finished
	await get_tree().create_timer(0.45).timeout
	var target := player.global_position
	var desired := atan2(-(target.x - customer.global_position.x), -(target.z - customer.global_position.z))
	var turn := create_tween()
	turn.tween_property(customer, "rotation:y", desired, 1.4).set_trans(Tween.TRANS_SINE)
	await turn.finished
	customer.body.turn_head_to(player.global_position + Vector3(0, 1.6, 0), true)
	AudioManager.stinger(false)
	await get_tree().create_timer(0.65).timeout
	_place_in_front(customer, 0.75)
	customer.body.turn_head_to(player.global_position + Vector3(0, 1.6, 0), true)
	AudioManager.play("door_slam", -6.0, 0.8)
	await get_tree().create_timer(0.12).timeout
	await _scare_beat(customer)


func _scare_register(customer: Customer) -> void:
	player.force_look_at(builder.register_body.global_position + Vector3(0, 1.5, 0), 1.0)
	customer.visible = false
	AudioManager.play("static", -4.0)
	Events.notify.emit("The register screen goes black.", "warn")
	await get_tree().create_timer(1.15).timeout
	_place_in_front(customer, 0.62)
	customer.visible = true
	customer.body.turn_head_to(player.global_position + Vector3(0, 1.6, 0), true)
	await _scare_beat(customer)


func _scare_lights(customer: Customer) -> void:
	customer.visible = false
	for light in builder.ceiling_lights:
		light.light_energy = 0.0
		var panel: Node = light.get_meta("panel", null)
		if panel and panel is MeshInstance3D:
			panel.visible = false
	AudioManager.play("breaker", -4.0)
	AudioManager.play("heartbeat", -8.0)
	await get_tree().create_timer(0.9).timeout
	for i in 5:
		AudioManager.play_at("step_%d" % _rng.randi_range(1, 4), player.global_position + Vector3(0, 0, 2.4 - i * 0.55), -4.0, 0.85)
		await get_tree().create_timer(0.34).timeout
	_restore_lights()
	_place_in_front(customer, 0.55)
	customer.visible = true
	await _scare_beat(customer)


func _scare_reflection(customer: Customer) -> void:
	customer.path = [Vector3(0.0, 0.0, 11.2)]
	customer.path_index = 0
	customer.set_state(Customer.State.WALKING)
	await customer.navigation_finished
	AudioManager.play_at("whisper", customer.global_position, -4.0)
	var fade := create_tween()
	fade.tween_property(customer, "scale", Vector3(0.02, 0.02, 0.02), 0.5)
	await fade.finished
	customer.visible = false
	customer.scale = Vector3.ONE
	await get_tree().create_timer(0.9).timeout
	var forward := -player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	customer.global_position = player.global_position - forward * 1.0
	customer.rotation.y = atan2(forward.x, forward.z)
	customer.visible = true
	player.force_look_at(customer.global_position + Vector3(0, 1.6, 0), 0.25)
	AudioManager.play_at("flesh", customer.global_position, -4.0)
	await _scare_beat(customer)


func _scare_counter(customer: Customer) -> void:
	AudioManager.play("door_slam", -4.0)
	builder.open_entrance(false)
	customer.visible = false
	await get_tree().create_timer(0.55).timeout
	customer.global_position = Vector3(1.9, 0.0, 9.35)
	customer.rotation.y = atan2(-(player.global_position.x - 1.9), -(player.global_position.z - 9.35))
	customer.visible = true
	player.force_look_at(customer.global_position + Vector3(0, 1.6, 0), 0.3)
	AudioManager.stinger(true)
	await get_tree().create_timer(0.4).timeout
	await _scare_beat(customer)


func _place_in_front(customer: Customer, distance: float) -> void:
	var forward := -player.camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length() < 0.01:
		forward = Vector3.FORWARD
	forward = forward.normalized()
	customer.global_position = player.global_position + forward * distance
	customer.rotation.y = atan2(forward.x, forward.z)
	if customer.body:
		customer.body.unfreeze()
		customer.body.set_skin_glitch(true)


func _scare_beat(customer: Customer) -> void:
	AudioManager.play("scream", 0.0)
	InputManager.vibrate(0.9, 1.0, 0.9)
	player.shake(0.07, 1.1)
	player.force_look_at(customer.global_position + Vector3(0, 1.6, 0), 2.0)
	Events.notify.emit("IT WAS NOT A PERSON.", "bad")
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(customer):
		var exit_tween := create_tween()
		exit_tween.tween_property(customer, "scale", Vector3(0.01, 0.01, 0.01), 0.35)
		await exit_tween.finished
		customer.queue_free()
