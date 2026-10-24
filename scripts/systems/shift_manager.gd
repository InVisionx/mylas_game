class_name ShiftManager
extends Node
## Orchestrates one shift: spawning, shopping, queueing, the active checkout,
## decisions, the clock and the end-of-shift report.

signal dialogue_requested(customer: Customer)
signal decision_resolved(correct: bool, message: String)

const CUSTOMER_SCENE := preload("res://scenes/customer/customer.tscn")
const MAX_IN_STORE := 3
const SPAWN_GAP := 7.0

var builder: StoreBuilder
var player: PlayerController
var checkout: CheckoutManager
var inspection: InspectionManager
var horror: Node

var customers: Array[Customer] = []
var queue: Array[Customer] = []
var active_customer: Customer = null

var shift_data: Dictionary = {}
var running := false
var served := 0
var customers_planned := 0
var time_left := 0.0
var spawned := 0

var rng := RandomNumberGenerator.new()
var _spawn_timer := 3.0
var _ending := false
var _entity_quota := 0
var _activation_timer := 0.0


func setup(refs: Dictionary) -> void:
	builder = refs.get("builder")
	player = refs.get("player")
	checkout = refs.get("checkout")
	inspection = refs.get("inspection")
	horror = refs.get("horror")
	add_to_group("shift_manager")
	if GameManager.shift_seed == 0:
		GameManager.new_shift_seed()
	rng.seed = GameManager.shift_seed


func start_shift() -> void:
	shift_data = GameManager.current_shift
	customers_planned = int(shift_data.get("customers", 6))
	time_left = float(shift_data.get("time_limit", 600))
	running = true
	_ending = false
	served = 0
	spawned = 0
	_spawn_timer = 3.5
	_entity_quota = int(shift_data.get("max_entities", 2))
	AudioManager.set_tension(int(shift_data.get("horror_level", 0)) + 1)
	Events.customer_count_changed.emit(0, customers_planned)
	Events.money_changed.emit(int(GameManager.profile.get("money", 0)), 0)
	Events.shift_started.emit(GameManager.shift_index, shift_data)
	Events.notify.emit("Shift started. Register online.", "info")


func _process(delta: float) -> void:
	if not running or _ending:
		return
	time_left = maxf(0.0, time_left - delta)
	if time_left <= 0.0:
		_end_shift(true, "Closing time. You did not finish the book.")
		return
	if served >= customers_planned:
		_end_shift(false, "")
		return
	_spawn_timer -= delta
	if _spawn_timer <= 0.0 and spawned < customers_planned and customers.size() < MAX_IN_STORE:
		_spawn_customer()
		_spawn_timer = SPAWN_GAP * rng.randf_range(0.75, 1.25)
	_activation_timer -= delta
	if _activation_timer <= 0.0:
		_activation_timer = 0.75
		if active_customer == null and not queue.is_empty():
			_try_activate_front()


func _spawn_customer(force_entity: bool = false) -> void:
	spawned += 1
	var customer := CUSTOMER_SCENE.instantiate() as Customer
	add_child(customer)
	customer.nav_graph = builder.nav_graph
	var entity_count := int(GameManager.session.get("entities_total", 0))
	if bool(shift_data.get("final_entity", false)) and spawned >= customers_planned:
		force_entity = true
	# Guarantee the night's minimum number of entities actually shows up.
	var min_entities := int(shift_data.get("min_entities", 0))
	var still_needed := maxi(0, min_entities - entity_count)
	var remaining_spawns := maxi(0, customers_planned - spawned)
	if still_needed > 0 and remaining_spawns <= still_needed:
		force_entity = true
	var force_human := entity_count >= _entity_quota and not force_entity
	customer.configure(spawned, shift_data, rng, force_entity, force_human)
	if customer.is_entity:
		GameManager.session["entities_total"] = entity_count + 1
	customer.global_position = StoreLayout.SPAWN_OUTSIDE + Vector3(rng.randf_range(-1.2, 1.2), 0.0, rng.randf_range(0.0, 2.0))
	customer.rotation.y = PI
	customers.append(customer)
	customer.left_store.connect(_on_customer_left)
	_run_customer(customer)


func _run_customer(customer: Customer) -> void:
	if builder:
		builder.open_entrance(true)
		AudioManager.play("door_chime", -15.0, rng.randf_range(0.96, 1.04))
	customer.goto_named("door", Customer.State.ENTERING)
	await customer.navigation_finished
	if not is_instance_valid(customer):
		return
	if builder:
		builder.open_entrance(false)

	var stops := rng.randi_range(1, 2)
	for i in stops:
		if not is_instance_valid(customer) or _ending:
			return
		var spot := _random_aisle_spot()
		customer.goto_position(spot, Customer.State.WALKING)
		await customer.navigation_finished
		if not is_instance_valid(customer):
			return
		customer.browse_for(rng.randf_range(2.2, 4.6), _shelf_face_for(spot))
		AudioManager.play_at("product_fall", spot, -30.0, rng.randf_range(1.1, 1.4))
		await customer.browse_finished
		if not is_instance_valid(customer):
			return

	queue.append(customer)
	_update_queue_positions()
	await customer.navigation_finished
	if not is_instance_valid(customer):
		return
	_try_activate_front()


func _random_aisle_spot() -> Vector3:
	var aisle_x := [-4.4, -0.8, 2.8, 6.6]
	var aisle_z := [2.6, -0.6, -4.2, -6.3]
	return Vector3(
		aisle_x[rng.randi_range(0, aisle_x.size() - 1)] + rng.randf_range(-0.35, 0.35),
		0.0,
		aisle_z[rng.randi_range(0, aisle_z.size() - 1)]
	)


func _shelf_face_for(spot: Vector3) -> Vector3:
	var best_x := spot.x
	var best_distance := INF
	for shelf in StoreLayout.SHELVES:
		var distance: float = absf(float(shelf["x"]) - spot.x)
		if distance < best_distance:
			best_distance = distance
			best_x = float(shelf["x"])
	return Vector3(best_x, 1.25, spot.z)


func _update_queue_positions() -> void:
	for i in queue.size():
		var customer := queue[i]
		if not is_instance_valid(customer):
			continue
		customer.queue_slot = i
		if i < StoreLayout.QUEUE_SPOTS.size():
			customer.goto_position(StoreLayout.QUEUE_SPOTS[i], Customer.State.QUEUEING)
	Events.queue_changed.emit(queue.size())


func _try_activate_front() -> void:
	if active_customer != null or queue.is_empty() or checkout == null:
		return
	var front := queue[0]
	if not is_instance_valid(front):
		queue.remove_at(0)
		return
	if front.state != Customer.State.QUEUEING:
		return
	if front.global_position.distance_to(StoreLayout.SERVICE_SPOT) > 1.35:
		return
	if not _player_behind_counter():
		return
	active_customer = front
	front.set_state(Customer.State.AT_COUNTER)
	front.at_counter = true
	if checkout.customer == front:
		return
	checkout.begin_customer(front)
	await get_tree().create_timer(0.9).timeout
	if not is_instance_valid(front):
		return
	front.speak_line(front.greeting())
	Events.customer_reached_counter.emit(front.customer_id)


func _player_behind_counter() -> bool:
	if player == null:
		return false
	var p := player.global_position
	return p.z > 8.35 and p.z < 11.5 and p.x > -2.6 and p.x < 4.2


func approve_customer() -> void:
	_decide(true)


func reject_customer() -> void:
	_decide(false)


func _decide(approved: bool) -> void:
	if active_customer == null or not is_instance_valid(active_customer):
		Events.notify.emit("Nobody is at the counter.", "warn")
		return
	if inspection != null and inspection.active:
		inspection.end()
	if approved and checkout != null and not checkout.is_ready_for_decision():
		Events.notify.emit("Scan everything before approving.", "warn")
		AudioManager.play("scan_fail", -12.0)
		return

	var customer := active_customer
	var total_cents := checkout.total_cents if checkout != null else customer.basket_total
	var result := GameManager.record_decision(approved, customer.is_entity, customer.full_name, total_cents)
	Events.decision_made.emit(customer.customer_id, approved)
	Events.decision_resolved.emit(customer.customer_id, approved, bool(result["correct"]), customer.is_entity)
	decision_resolved.emit(bool(result["correct"]), str(result["message"]))
	Events.notify.emit(str(result["message"]), "good" if bool(result["correct"]) else "bad")

	active_customer = null
	if queue.has(customer):
		queue.erase(customer)
	served += 1
	Events.customer_count_changed.emit(served, customers_planned)
	if checkout != null:
		checkout.finish_transaction()

	if customer.is_entity and approved:
		GameManager.session["jumpscares"] = int(GameManager.session.get("jumpscares", 0)) + 1
		_play_escape(customer)
	else:
		if builder:
			builder.open_entrance(true)
		if not approved and customer.is_entity:
			customer.speak_line(GameData.entity_line("departing", rng))
		customer.leave_store(approved)
		if approved and customer.has_anomaly("receipt_message"):
			_print_receipt(customer)
		_update_queue_positions()
		if not queue.is_empty():
			await get_tree().create_timer(1.4).timeout
			_try_activate_front()


func _print_receipt(customer: Customer) -> void:
	if builder == null:
		return
	AudioManager.play("receipt", -8.0)
	Events.receipt_printed.emit("THANK YOU FOR LETTING ME.")
	builder.set_register_text("THANK YOU FOR LETTING ME", Color(1.0, 0.3, 0.3))
	for anomaly in customer.anomalies:
		if str(anomaly.get("id", "")) == "receipt_message":
			customer.reveal_clue(anomaly)
			break


func _play_escape(customer: Customer) -> void:
	if horror != null and horror.has_method("play_entity_departure"):
		horror.call("play_entity_departure", customer)
	await get_tree().create_timer(0.1).timeout
	_update_queue_positions()
	var penalty_mode := str(shift_data.get("penalty_mode", "fine"))
	if penalty_mode == "fail":
		await get_tree().create_timer(4.5).timeout
		_end_shift(true, "It paid and left. The store is not yours anymore.")
	elif not queue.is_empty():
		await get_tree().create_timer(3.0).timeout
		_try_activate_front()


func _on_customer_left(customer: Customer) -> void:
	customers.erase(customer)
	if is_instance_valid(customer):
		customer.queue_free()
	if builder:
		var anyone_leaving := false
		for other in customers:
			if is_instance_valid(other) and other.state == Customer.State.LEAVING:
				anyone_leaving = true
				break
		if not anyone_leaving:
			builder.open_entrance(false)


func open_dialogue(customer: Customer) -> void:
	if customer == null or not is_instance_valid(customer):
		return
	if active_customer != customer and customer.state != Customer.State.QUEUEING:
		return
	dialogue_requested.emit(customer)


func _end_shift(failed: bool, reason: String) -> void:
	if _ending:
		return
	_ending = true
	running = false
	if inspection != null and inspection.active:
		inspection.end()
	AudioManager.set_tension(0)
	GameManager.finish_shift(failed, reason)


func remaining_time_string() -> String:
	var total := int(maxf(time_left, 0.0))
	return "%02d:%02d" % [total / 60, total % 60]


func current_customer() -> Customer:
	return active_customer
