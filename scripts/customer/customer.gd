class_name Customer
extends CharacterBody3D
## One shopper. Holds their identity, their anomalies, their basket and the
## walk/shop/queue/checkout/leave state machine.

signal reached_counter(customer: Customer)
signal left_store(customer: Customer)
signal customer_spoke(customer: Customer, text: String)
signal navigation_finished(customer: Customer)
signal browse_finished(customer: Customer)

enum State { ENTERING, WALKING, BROWSING, QUEUEING, AT_COUNTER, LEAVING, GONE }

const FIRST_NAMES := [
	"Dale", "Mira", "Owen", "Tess", "Harold", "June", "Marcus", "Nia",
	"Peter", "Rosa", "Sam", "Vera", "Wes", "Yara", "Ellis", "Dana",
	"Colin", "Ruth", "Aaron", "Faye", "Vince", "Lena", "Gus", "Odalys",
]
const LAST_NAMES := [
	"Hollis", "Brant", "Okonkwo", "Vance", "Marsh", "Doyle", "Petrov", "Sato",
	"Ellery", "Cruz", "Nash", "Ambrose", "Weiss", "Mbeki", "Kaur", "Lindqvist",
]

var customer_id := 0
var full_name := "Customer"
var personality: Dictionary = {}
var personality_id := "friendly"
var is_entity := false
var anomalies: Array = []
var harmless_trait: Dictionary = {}
var basket: Array = []
var basket_total := 0

var state: State = State.ENTERING
var body: CustomerBody
var speed := 1.1
var patience := 40.0

var nav_graph: AStar3D
var path: Array = []
var path_index := 0
var queue_slot := -1
var at_counter := false

var approved := false
var finished := false
var clues_revealed: Array = []
var questions_asked := 0

var _browse_timer := 0.0
var _freeze_timer := 0.0
var _frozen_for := 0.0
var _stare := false
var _eye_track := false
var _breath_sound_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _time := 0.0
var _last_answer := ""
var _voice_pitch := 1.0
var _leaving_target := Vector3.ZERO
var _idle_timer := 0.0

const IDLE_LINES := ["...", "Ready when you are.", "You're staring.", "Everything all right?"]
const ENTITY_IDLE_LINES := ["Take your time. I have all night.", "I do not mind waiting. I am very patient.", "You have not scanned the last one yet."]

@onready var collision: CollisionShape3D = $Collision


func configure(id: int, shift: Dictionary, rng: RandomNumberGenerator, force_entity: bool = false, force_human: bool = false) -> void:
	customer_id = id
	_rng.seed = rng.randi()
	personality = GameData.random_personality(rng)
	personality_id = str(personality.get("id", "friendly"))
	full_name = "%s %s" % [
		FIRST_NAMES[rng.randi_range(0, FIRST_NAMES.size() - 1)],
		LAST_NAMES[rng.randi_range(0, LAST_NAMES.size() - 1)],
	]
	speed = 1.05 * float(personality.get("speed", 1.0))
	patience = 42.0 * float(personality.get("patience", 1.0)) * float(shift.get("patience_scale", 1.0))

	is_entity = (force_entity or rng.randf() < float(shift.get("entity_chance", 0.3))) and not force_human
	if is_entity:
		var min_count := int(shift.get("min_anomalies", 1))
		var max_count := int(shift.get("max_anomalies", 2))
		var count := rng.randi_range(min_count, maxi(max_count, min_count))
		anomalies = GameData.roll_anomalies(count, shift, rng)
		# Entities must always carry at least one detectable clue.
		if anomalies.is_empty():
			anomalies = GameData.roll_anomalies(1, shift, rng)
	else:
		if rng.randf() < float(shift.get("harmless_trait_chance", 0.2)):
			harmless_trait = GameData.random_harmless_trait(rng)

	var item_count := rng.randi_range(int(shift.get("items_min", 3)), int(shift.get("items_max", 6)))
	basket = GameData.random_products(item_count, rng)
	basket_total = 0
	for product in basket:
		basket_total += int(product.get("price", 0))

	# Entities with a checkout anomaly may smuggle in something impossible.
	for anomaly in anomalies:
		if str(anomaly.get("id", "")) == "extra_item":
			var impossible := GameData.random_impossible_item(rng)
			if not impossible.is_empty():
				basket.append(impossible)
				break

	_voice_pitch = rng.randf_range(0.8, 1.25)
	_build_body(rng)
	if is_entity:
		for anomaly in anomalies:
			var visual := str(anomaly.get("visual", {}).get("kind", ""))
			match visual:
				"stare":
					_stare = true
				"eye_track":
					_eye_track = true
				"wrong_shadow":
					body.set_meta("lag_shadow", true)
				"freeze":
					_freeze_timer = _rng.randf_range(8.0, 14.0)
				"breath_sound":
					_breath_sound_timer = 4.0
				"camera_shape":
					body.set_silhouette()
		# The "stare"/"freeze" behaviours are behavioural anomalies, not visuals.
		if has_anomaly("stares"):
			_stare = true
		if has_anomaly("freezes"):
			_freeze_timer = _rng.randf_range(9.0, 16.0)
		if has_anomaly("bad_breathing"):
			_breath_sound_timer = 5.0
		if has_anomaly("eyes_track"):
			_eye_track = true
		if has_anomaly("wrong_shadow"):
			body.set_meta("lag_shadow", true)


func _build_body(rng: RandomNumberGenerator) -> void:
	body = CustomerBody.new()
	body.name = "Body"
	add_child(body)
	body.build(rng.randi(), {
		"height_scale": rng.randf_range(0.9, 1.1),
		"body_width": rng.randf_range(0.88, 1.16),
		"anomalies": anomalies,
	})
	var capsule := (collision.shape as CapsuleShape3D)
	if capsule:
		capsule.height = 1.76 * body.height_scale
		collision.position.y = capsule.height * 0.5


func _ready() -> void:
	add_to_group("customers")
	if body == null:
		_build_body(_rng)
	Events.horror_event_started.connect(_on_horror_event)


# --- Navigation -------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_time += delta
	if not is_on_floor():
		velocity.y -= 18.0 * delta
	else:
		velocity.y = -0.1

	var move_speed := 0.0
	match state:
		State.ENTERING, State.WALKING, State.QUEUEING, State.LEAVING:
			move_speed = _follow_path(delta)
		State.BROWSING:
			_browse(delta)
		State.AT_COUNTER:
			velocity.x = move_toward(velocity.x, 0.0, 24.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 24.0 * delta)
		_:
			velocity.x = move_toward(velocity.x, 0.0, 24.0 * delta)
			velocity.z = move_toward(velocity.z, 0.0, 24.0 * delta)

	move_and_slide()
	_update_behavior(delta)
	if state == State.GONE and global_position.y < -5.0:
		queue_free()


func goto_named(waypoint_id: String, new_state: State = State.WALKING) -> void:
	var all_points := StoreLayout.waypoints()
	var fallback := Vector3.ZERO
	if all_points.has(waypoint_id):
		fallback = all_points[waypoint_id]
	if nav_graph == null:
		if fallback != Vector3.ZERO:
			path = [fallback]
			path_index = 0
			state = new_state
		return
	var target_index := StoreLayout.waypoint_index(nav_graph, waypoint_id)
	var start_index := _nearest_node_with_line_of_sight()
	if target_index < 0 or start_index < 0:
		if fallback != Vector3.ZERO:
			path = [fallback]
			path_index = 0
			state = new_state
		return
	path = Array(nav_graph.get_point_path(start_index, target_index))
	path_index = 0
	state = new_state


func goto_position(point: Vector3, new_state: State = State.QUEUEING) -> void:
	if nav_graph == null:
		path = [point]
		path_index = 0
		state = new_state
		return
	var start_index := _nearest_node_with_line_of_sight()
	if start_index < 0:
		path = [point]
		path_index = 0
		state = new_state
		return
	var all_points := nav_graph.get_point_ids()
	var best := -1
	var best_distance := INF
	var flat := Vector3(point.x, 0.0, point.z)
	for id in all_points:
		var p: Vector3 = nav_graph.get_point_position(id)
		if StoreLayout.segment_blocked(p, flat):
			continue
		var distance := p.distance_to(flat)
		if distance < best_distance:
			best_distance = distance
			best = id
	if best < 0:
		path = [point]
	else:
		path = Array(nav_graph.get_point_path(start_index, best))
	path.append(point)
	path_index = 0
	state = new_state


func _nearest_node_with_line_of_sight() -> int:
	if nav_graph == null:
		return -1
	var best := -1
	var best_distance := INF
	var origin := Vector3(global_position.x, 0.0, global_position.z)
	for id in nav_graph.get_point_ids():
		var p: Vector3 = nav_graph.get_point_position(id)
		if StoreLayout.segment_blocked(origin, p):
			continue
		var distance := origin.distance_to(p)
		if distance < best_distance:
			best_distance = distance
			best = id
	if best >= 0:
		return best
	# Fallback: nearest point even if the straight line clips something.
	for id in nav_graph.get_point_ids():
		var p: Vector3 = nav_graph.get_point_position(id)
		var distance := origin.distance_to(p)
		if distance < best_distance:
			best_distance = distance
			best = id
	return best


func _follow_path(delta: float) -> float:
	if _frozen_for > 0.0:
		_frozen_for -= delta
		velocity.x = 0.0
		velocity.z = 0.0
		if _frozen_for <= 0.0:
			body.unfreeze()
		return 0.0
	if path.is_empty() or path_index >= path.size():
		return 0.0
	var target: Vector3 = path[path_index]
	target.y = global_position.y
	var to_target := target - global_position
	to_target.y = 0.0
	if to_target.length() < 0.30:
		path_index += 1
		if path_index >= path.size():
			_navigation_finished()
			return 0.0
		return speed
	var direction := to_target.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), 9.0 * delta)
	return speed


func _navigation_finished() -> void:
	match state:
		State.BROWSING:
			pass
		State.LEAVING:
			state = State.GONE
			left_store.emit(self)
		_:
			state = State.WALKING
	navigation_finished.emit(self)


func _browse(delta: float) -> void:
	_browse_timer -= delta
	velocity.x = 0.0
	velocity.z = 0.0
	if _browse_timer <= 0.0:
		state = State.WALKING
		browse_finished.emit(self)


func browse_for(seconds: float, look_point: Vector3 = Vector3.ZERO) -> void:
	_browse_timer = seconds
	state = State.BROWSING
	velocity = Vector3.ZERO
	body.raise_arm("right")
	if look_point != Vector3.ZERO:
		rotation.y = atan2(-(look_point.x - global_position.x), -(look_point.z - global_position.z))


func _update_behavior(delta: float) -> void:
	if body == null:
		return
	var player := get_tree().get_first_node_in_group("player") as Node3D
	var look_target := Vector3.ZERO
	if player != null and (state == State.AT_COUNTER or state == State.QUEUEING or _stare):
		look_target = player.global_position + Vector3(0, 1.55, 0)
	elif _eye_track and player != null:
		look_target = player.global_position + Vector3(0, 1.6, 0)

	body.animate(delta, Vector2(velocity.x, velocity.z).length(), look_target)

	if body.has_meta("lag_shadow"):
		body.set_shadow_lag(sin(_time * 1.4) * 0.18 + (0.12 if state != State.AT_COUNTER else 0.0))

	# Periodic total stillness: the player has to notice it.
	if _freeze_timer > 0.0 and _frozen_for <= 0.0:
		_freeze_timer -= delta
		if _freeze_timer <= 0.0:
			body.freeze()
			_frozen_for = 2.6
			_freeze_timer = 0.0

	if _breath_sound_timer > 0.0:
		_breath_sound_timer -= delta
		if _breath_sound_timer <= 0.0:
			AudioManager.play_at("breath", global_position + Vector3(0, 1.4, 0), -6.0, 0.85)
			_breath_sound_timer = _rng.randf_range(5.0, 8.0)

	# Someone who has been standing at the counter too long says so.
	if state == State.AT_COUNTER:
		if player != null:
			var to_player := player.global_position - global_position
			to_player.y = 0.0
			if to_player.length() > 0.05:
				var desired_yaw := atan2(-to_player.x, -to_player.z)
				rotation.y = lerp_angle(rotation.y, desired_yaw, delta * 2.6)
		_idle_timer += delta
		if _idle_timer > 22.0:
			_idle_timer = 0.0
			var pool: Array = ENTITY_IDLE_LINES if is_entity else IDLE_LINES
			speak_line(str(pool[_rng.randi_range(0, pool.size() - 1)]))


func _on_horror_event(event_id: String) -> void:
	if event_id != "lights_flicker":
		return
	if has_anomaly("face_flickers"):
		body.set_skin_glitch(true)
		await get_tree().create_timer(0.18).timeout
		if is_instance_valid(body):
			body.set_skin_glitch(false)


# --- Identity / checks ------------------------------------------------------

func has_anomaly(id: String) -> bool:
	for anomaly in anomalies:
		if str(anomaly.get("id", "")) == id:
			return true
	return false


func anomalies_with_focus(focus: String) -> Array:
	var result: Array = []
	for anomaly in anomalies:
		if str(anomaly.get("focus", "")) == focus:
			result.append(anomaly)
	return result


func harmless_trait_focus() -> String:
	return str(harmless_trait.get("focus", ""))


func reveal_clue(anomaly: Dictionary) -> bool:
	var id := str(anomaly.get("id", ""))
	if id.is_empty() or clues_revealed.has(id):
		return false
	clues_revealed.append(id)
	var is_new := GameManager.add_clue(id)
	Events.clue_found.emit(id, str(anomaly.get("description", "")))
	if is_new:
		Events.notify.emit("CLUE LOGGED — %s" % str(anomaly.get("label", "Something odd")), "clue")
	return true


func clue_count() -> int:
	return clues_revealed.size()


func suspicion() -> float:
	if anomalies.is_empty():
		return 0.0
	return clampf(float(clues_revealed.size()) / float(anomalies.size()), 0.0, 1.0)


func is_being_served() -> bool:
	return state == State.AT_COUNTER


func get_interact_prompt() -> String:
	if state == State.AT_COUNTER:
		return "TALK TO %s  ·  [X] INSPECT" % full_name.to_upper()
	if state == State.QUEUEING:
		return "TALK TO %s" % full_name.to_upper()
	return ""


func interact(_player: Node = null) -> void:
	var manager := get_tree().get_first_node_in_group("shift_manager")
	if manager != null and manager.has_method("open_dialogue"):
		manager.call("open_dialogue", self)


# --- Inspection anchors -----------------------------------------------------

func focus_anchor(focus: String) -> Vector3:
	if body == null:
		return global_position + Vector3(0, 1.5, 0)
	match focus:
		"face":
			return body.head_anchor().global_position + Vector3(0, 0.02, 0)
		"eyes":
			return body.eyes_anchor().global_position
		"mouth":
			return body.mouth.global_position
		"neck":
			return body.neck.global_position
		"hands":
			return body.hand_anchor().global_position
		"posture":
			return body.torso.global_position
		"reflection":
			return global_position + Vector3(0, 1.5, 0)
		"shadow":
			return global_position + Vector3(0, 0.1, 0)
		_:
			return global_position + Vector3(0, 1.4, 0)


# --- Dialogue ---------------------------------------------------------------

func greeting() -> String:
	if is_entity and _rng.randf() < 0.5:
		return GameData.entity_line("greeting", _rng)
	return GameData.personality_greeting(personality_id, _rng)


func answer(question_id: String) -> String:
	questions_asked += 1
	var line := ""
	if has_anomaly("repeat_sentence"):
		if _last_answer.is_empty():
			_last_answer = GameData.entity_line("loop", _rng)
		line = _last_answer
	elif has_anomaly("knows_too_much") and questions_asked >= 2:
		line = GameData.entity_line("knows", _rng)
	elif has_anomaly("wrong_answer") and questions_asked >= 2:
		line = GameData.entity_line("wrong_question", _rng)
	elif is_entity and _rng.randf() < 0.22:
		line = GameData.entity_line("wrong", _rng)
	else:
		line = GameData.personality_line(personality_id, question_id, _rng)
	_last_answer = line
	body.speak()
	AudioManager.voice_blip(_voice_pitch, -14.0)
	customer_spoke.emit(self, line)
	Events.dialogue_line.emit(full_name, line)
	return line


func speak_line(text: String) -> void:
	body.speak()
	AudioManager.voice_blip(_voice_pitch, -14.0)
	customer_spoke.emit(self, text)
	Events.dialogue_line.emit(full_name, text)


func set_state(new_state: State) -> void:
	state = new_state


# --- Exit -------------------------------------------------------------------

func leave_store(was_approved: bool) -> void:
	approved = was_approved
	at_counter = false
	path = []
	path_index = 0
	state = State.LEAVING
	var route: Array = StoreLayout.EXIT_ROUTE.duplicate()
	path = route
	path_index = 0
	if is_entity and was_approved:
		var scare_manager := get_tree().get_first_node_in_group("horror_director")
		if scare_manager != null and scare_manager.has_method("play_entity_departure"):
			scare_manager.call("play_entity_departure", self)


func _exit_tree() -> void:
	InputManager.vibrate(0.0, 0.0, 0.0)
