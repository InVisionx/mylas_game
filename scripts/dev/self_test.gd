extends Node
## Headless smoke test that exercises the real game systems.
##
##   godot --headless --path . -- --night=1 --selftest
##
## Prints [OK]/[FAIL] lines and exits non-zero if anything is broken.

var _failures := 0
var _checks := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("[OK]   %s   %s" % [label, detail])
	else:
		_failures += 1
		print("[FAIL] %s   %s" % [label, detail])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Scans whatever is still on the belt until the checkout reports ready.
func _scan_everything(checkout: CheckoutManager, timeout: float = 15.0) -> void:
	var elapsed := 0.0
	while not checkout.is_ready_for_decision() and elapsed < timeout:
		var target: ProductItem = null
		for item in checkout.items:
			if is_instance_valid(item) and not item.scanned:
				target = item
				break
		if target != null:
			checkout.scan_item(target)
		await _wait(0.5)
		elapsed += 0.5


func _run() -> void:
	var store: Node = null
	for i in 400:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == "Store":
			store = get_tree().current_scene
			break
	_check("store scene loaded", store != null)
	if store == null:
		_finish()
		return

	await _wait(0.8)
	var builder = store.get_node("StoreBuilder")
	var player = store.get_node("Player")
	var shift = store.get_node("ShiftManager")
	var checkout = store.get_node("Checkout")
	var inspection = store.get_node("Inspection")
	var hud = store.get_node("HUD")

	# --- World --------------------------------------------------------------
	_check("nav graph built", builder.nav_graph != null)
	if builder.nav_graph != null:
		_check("nav graph has points", builder.nav_graph.get_point_count() > 10, str(builder.nav_graph.get_point_count()))
		var door_index := StoreLayout.waypoint_index(builder.nav_graph, "door")
		var queue_index := StoreLayout.waypoint_index(builder.nav_graph, "queue_back")
		var path: Array = []
		if door_index >= 0 and queue_index >= 0:
			path = builder.nav_graph.get_point_path(door_index, queue_index)
		_check("door to queue is walkable", path.size() > 0, "%d steps" % path.size())
		var unreachable: Array = []
		var points := StoreLayout.waypoints()
		for id in points.keys():
			if id == "door":
				continue
			var index := StoreLayout.waypoint_index(builder.nav_graph, id)
			if index < 0 or builder.nav_graph.get_point_path(door_index, index).is_empty():
				unreachable.append(id)
		_check("every waypoint is reachable", unreachable.is_empty(), str(unreachable))
	var mesh_count := _count_meshes(builder)
	_check("world has geometry", mesh_count > 100, "%d meshes" % mesh_count)
	_check("world has colliders", builder.world_body.get_child_count() > 20, "%d colliders" % builder.world_body.get_child_count())
	_check("player at counter", player.global_position.distance_to(StoreLayout.PLAYER_START) < 0.5)
	_check("register ready", builder.register_screen != null)
	_check("security monitor attached", builder.security_monitor != null)
	_check("audio library built", AudioManager.has_sound("scan") and AudioManager.has_sound("scream"))

	# --- Waiting customer ---------------------------------------------------
	var spawned: Customer = null
	for i in 500:
		await get_tree().process_frame
		for node in get_tree().get_nodes_in_group("customers"):
			if node is Customer:
				spawned = node
				break
		if spawned != null:
			break
	_check("customer spawned", spawned != null)
	if spawned == null:
		_finish()
		return
	_check("customer has generated body", spawned.body != null and spawned.body.head != null)
	_check("customer has basket", spawned.basket.size() >= 3, "%d items" % spawned.basket.size())

	var start_pos := spawned.global_position
	spawned.goto_named("door")
	await _wait(2.5)
	_check("customer walks toward the door", spawned.global_position.distance_to(start_pos) > 0.5,
		"moved %.2fm" % spawned.global_position.distance_to(start_pos))

	# --- The real loop: enter, shop, queue, arrive at the counter -----------
	var waited_activation := 0.0
	while shift.active_customer == null and waited_activation < 55.0:
		await _wait(0.5)
		waited_activation += 0.5
	_check("customer reached the counter on their own", shift.active_customer != null,
		"after %.1fs" % waited_activation)

	# --- Checkout -----------------------------------------------------------
	var human: Customer = shift.active_customer
	if human == null:
		human = spawned
		human.is_entity = false
		human.anomalies = []
		human.global_position = StoreLayout.SERVICE_SPOT
		human.set_state(Customer.State.AT_COUNTER)
		human.velocity = Vector3.ZERO
		shift.active_customer = human
		shift.queue.clear()
		shift.queue.append(human)
		checkout.begin_customer(human)
	else:
		human.is_entity = false
		human.anomalies = []
	var waited := 0.0
	while checkout.items.size() < human.basket.size() and waited < 8.0:
		await _wait(0.2)
		waited += 0.2
	_check("basket placed on belt", checkout.items.size() == human.basket.size(),
		"%d/%d" % [checkout.items.size(), human.basket.size()])

	var money_before := int(GameManager.profile.get("money", 0))
	var served_before := int(GameManager.session.get("served", 0))
	await _scan_everything(checkout)
	_check("all items scanned", checkout.is_ready_for_decision(), "%d scanned, %d cents" % [checkout.scanned_count, checkout.total_cents])
	_check("scanner total is positive", checkout.total_cents > 0, GameData.price_string(checkout.total_cents))

	shift.approve_customer()
	await _wait(0.6)
	_check("human approval counted", int(GameManager.session.get("served", 0)) == served_before + 1)
	_check("human approval paid out", int(GameManager.profile.get("money", 0)) > money_before,
		"%d -> %d" % [money_before, int(GameManager.profile.get("money", 0))])

	# --- The customer must be able to walk out of the store -----------------
	var left_store := false
	for i in 60:
		await _wait(0.25)
		if not is_instance_valid(human) or human.global_position.z > 13.0:
			left_store = true
			break
	_check("served customer walks out the doors", left_store)

	# Freeze spawning so the scripted customers below are not re-queued by the
	# live shift while we exercise them deterministically.
	shift.running = false

	# --- Entity inspection + jumpscare -------------------------------------
	var entity := preload("res://scenes/customer/customer.tscn").instantiate() as Customer
	store.add_child(entity)
	entity.nav_graph = builder.nav_graph
	entity.configure(777, shift.shift_data, shift.rng, true)
	entity.global_position = StoreLayout.SERVICE_SPOT
	entity.set_state(Customer.State.AT_COUNTER)
	shift.active_customer = entity
	await _wait(0.2)
	_check("entity has anomalies", entity.anomalies.size() > 0, str(entity.anomalies.size()))

	inspection.begin(entity)
	await _wait(0.2)
	var focus := str(entity.anomalies[0].get("focus", "hands"))
	inspection._focus_index = maxi(StoreLayout.FOCUS_ORDER.find(focus), 0)
	inspection._apply_focus()
	entity.set_state(Customer.State.AT_COUNTER)
	inspection._resolve_focus()
	await _wait(0.2)
	_check("inspection reveals a clue", entity.clues_revealed.size() > 0, str(entity.clues_revealed))
	_check("clue persisted to notebook", GameManager.discovered_count() > 0, str(GameManager.discovered_count()))
	inspection.end()

	checkout.begin_customer(entity)
	waited = 0.0
	while checkout.items.size() < entity.basket.size() and waited < 6.0:
		await _wait(0.2)
		waited += 0.2
	await _scan_everything(checkout)

	var approved_before := int(GameManager.session.get("entities_approved", 0))
	var penalties_before := int(GameManager.session.get("penalty", 0))
	shift.approve_customer()
	await _wait(7.0)
	_check("entity approval registered", int(GameManager.session.get("entities_approved", 0)) == approved_before + 1)
	_check("entity approval fined the player", int(GameManager.session.get("penalty", 0)) > penalties_before,
		"penalty %d" % int(GameManager.session.get("penalty", 0)))

	# --- Save / report ------------------------------------------------------
	var report := GameManager.finish_shift(false, "")
	_check("report produced", report.has("accuracy") and report.has("money"))
	_check("save file written", FileAccess.file_exists("user://nightsave.json"))
	_check("HUD alive", hud != null and hud.shift_label != null)

	# --- Security feed, notebook, quality lever -----------------------------
	var security = store.get_node("SecurityMonitor")
	var feed_before := str(security.feed_label())
	security.cycle_feed()
	await _wait(0.1)
	_check("security feed cycles", str(security.feed_label()) != feed_before,
		"%s -> %s" % [feed_before, str(security.feed_label())])

	var notebook = store.get_node("Notebook")
	notebook.open()
	await _wait(0.1)
	_check("notebook opens", notebook.visible)
	notebook.close()
	_check("notebook closes", not notebook.visible)

	var pause_menu = store.get_node("PauseMenu")
	pause_menu.toggle()
	await _wait(0.15)
	_check("pause menu opens and pauses", pause_menu.visible and get_tree().paused)
	pause_menu.toggle()
	await _wait(0.15)
	_check("pause menu closes and resumes", not pause_menu.visible and not get_tree().paused)

	SettingsManager.set_graphics_value("quality", 0)
	await _wait(0.1)
	var visible_lights := 0
	for light in get_tree().get_nodes_in_group("ambience_lights"):
		if light is Node3D and light.visible:
			visible_lights += 1
	_check("low quality trims fill lights", visible_lights <= 2, "%d lights" % visible_lights)
	SettingsManager.set_graphics_value("quality", 1)

	# --- Human rejection ----------------------------------------------------
	var rejectee := preload("res://scenes/customer/customer.tscn").instantiate() as Customer
	store.add_child(rejectee)
	rejectee.nav_graph = builder.nav_graph
	rejectee.configure(888, shift.shift_data, shift.rng, false, true)
	rejectee.global_position = StoreLayout.SERVICE_SPOT
	rejectee.set_state(Customer.State.AT_COUNTER)
	shift.active_customer = rejectee
	await _wait(0.2)
	var fine_before := int(GameManager.session.get("penalty", 0))
	var served_pre_reject := int(GameManager.session.get("served", 0))
	shift.reject_customer()
	await _wait(0.6)
	_check("rejecting a human is fined", int(GameManager.session.get("penalty", 0)) > fine_before)
	_check("rejection counted as served", int(GameManager.session.get("served", 0)) == served_pre_reject + 1)

	_finish()


func _count_meshes(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D:
		total += 1
	for child in node.get_children():
		total += _count_meshes(child)
	return total


func _finish() -> void:
	print("----- SELF TEST: %d checks, %d failures -----" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)
