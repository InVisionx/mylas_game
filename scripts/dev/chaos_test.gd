extends Node
## Chaos test: hammers the transitions that are most likely to crash — entity
## approvals (jumpscares), pausing and opening the notebook mid-scare, ending a
## failed shift and reloading the store scene.
##
##   godot --headless --path . -- --night=4 --chaos

const CUSTOMER_SCENE := preload("res://scenes/customer/customer.tscn")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	var store := await _wait_for_store()
	if store == null:
		print("[CHAOS] store never loaded")
		get_tree().quit(1)
		return

	var rounds := 6
	for round_index in rounds:
		store = get_tree().current_scene
		if store == null or store.name != "Store":
			await _wait(1.0)
			store = get_tree().current_scene
		var builder = store.get_node("StoreBuilder")
		var shift = store.get_node("ShiftManager")
		var checkout = store.get_node("Checkout")
		var pause_menu = store.get_node("PauseMenu")
		var notebook = store.get_node("Notebook")

		var entity := CUSTOMER_SCENE.instantiate() as Customer
		store.add_child(entity)
		entity.nav_graph = builder.nav_graph
		entity.configure(900 + round_index, shift.shift_data, shift.rng, true)
		entity.global_position = StoreLayout.SERVICE_SPOT
		entity.set_state(Customer.State.AT_COUNTER)
		shift.active_customer = entity
		await _wait(0.3)

		checkout.begin_customer(entity)
		await _wait(2.5)
		for item in checkout.items.duplicate():
			if is_instance_valid(item):
				checkout.scan_item(item)
				await _wait(0.45)
		shift.approve_customer()

		# Overlap UI with the running jumpscare.
		await _wait(0.7)
		pause_menu.toggle()
		await _wait(0.25)
		pause_menu.toggle()
		notebook.open()
		await _wait(0.2)
		notebook.close()
		await _wait(0.4)
		pause_menu.toggle()
		await _wait(0.2)
		pause_menu.toggle()
		await _wait(4.5)

		GameManager.finish_shift(true, "chaos round %d" % round_index)
		await _wait(0.8)
		print("[CHAOS] round %d: obj=%d nodes=%d orphans=%d mem=%.2fMB" % [
			round_index,
			int(Performance.get_monitor(Performance.OBJECT_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
			int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
			OS.get_static_memory_usage() / 1048576.0,
		])
		GameManager.continue_after_report()
		await _wait(2.5)

	print("[CHAOS] completed %d rounds without crashing" % rounds)
	get_tree().quit(0)


func _wait_for_store() -> Node:
	for i in 600:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == "Store":
			return get_tree().current_scene
	return null
