extends Node
## Soak test: plays the shift loop continuously and samples engine counters.
##
##   godot --headless --path . -- --night=1 --soak
##   godot --headless --path . -- --night=1 --soak --minutes=6
##
## Prints a sample every 10s and a delta summary at the end. A steady climb in
## objects/nodes/memory means a leak somewhere in the loop.

var _samples: Array = []
var _served := 0
var _rejected_entities := 0
var _approved_entities := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _minutes() -> float:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--minutes="):
			return float(arg.get_slice("=", 1))
	return 4.0


func _run() -> void:
	var store: Node = null
	for i in 600:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == "Store":
			store = get_tree().current_scene
			break
	if store == null:
		print("[SOAK] store never loaded")
		get_tree().quit(1)
		return

	var shift = store.get_node("ShiftManager")
	var checkout = store.get_node("Checkout")
	await get_tree().create_timer(1.0).timeout

	# Keep the shift open so we are churning the loop, not the report screen.
	shift.customers_planned = 1000000
	shift.time_left = 1000000.0
	shift.running = true

	print("[SOAK] starting %.1f minute run" % _minutes())
	var start_ticks := Time.get_ticks_msec()
	var next_sample := 0.0
	var judge_timer := 0.0

	while true:
		var elapsed := (Time.get_ticks_msec() - start_ticks) / 1000.0
		if elapsed >= _minutes() * 60.0:
			break
		await get_tree().create_timer(0.25).timeout

		# Auto-serve whatever is at the counter.
		judge_timer += 0.25
		if judge_timer >= 0.5:
			judge_timer = 0.0
			_autoplay(shift, checkout)

		if elapsed >= next_sample:
			next_sample = elapsed + 10.0
			_sample(store, shift, checkout, elapsed)

	_summary(store, shift, checkout)
	get_tree().quit(0)


func _autoplay(shift, checkout) -> void:
	var customer = shift.active_customer
	if customer == null or not is_instance_valid(customer):
		return
	if not checkout.active:
		return
	if checkout.is_ready_for_decision():
		if customer.is_entity:
			_rejected_entities += 1
			shift.reject_customer()
		else:
			shift.approve_customer()
		_served += 1
		return
	# Scan one item at a time so the real async scan path is exercised.
	for item in checkout.items:
		if is_instance_valid(item) and not item.scanned:
			checkout.scan_item(item)
			return


func _sample(store: Node, shift, checkout, elapsed: float) -> void:
	var row := {
		"t": snappedf(elapsed, 0.1),
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"orphans": Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),
		"mem_mb": snappedf(OS.get_static_memory_usage() / 1048576.0, 0.01),
		"fps": int(Performance.get_monitor(Performance.TIME_FPS)),
		"customers": shift.customers.size(),
		"queue": shift.queue.size(),
		"items": checkout.items.size(),
		"served": _served,
	}
	_samples.append(row)
	print("[SOAK] t=%5.1fs obj=%6d nodes=%5d orphans=%4d mem=%7.2fMB fps=%3d cust=%d q=%d items=%d served=%d" % [
		row["t"], row["objects"], row["nodes"], row["orphans"], row["mem_mb"], row["fps"],
		row["customers"], row["queue"], row["items"], row["served"],
	])


func _summary(store: Node, shift, checkout) -> void:
	print("[SOAK] served=%d rejected_entities=%d" % [_served, _rejected_entities])
	if _samples.size() < 2:
		return
	var first: Dictionary = _samples[2] if _samples.size() > 3 else _samples[0]
	var last: Dictionary = _samples[_samples.size() - 1]
	print("[SOAK] delta objects=%+d nodes=%+d orphans=%+d mem=%+.2fMB over %.0fs" % [
		last["objects"] - first["objects"],
		last["nodes"] - first["nodes"],
		last["orphans"] - first["orphans"],
		last["mem_mb"] - first["mem_mb"],
		last["t"] - first["t"],
	])
	# Per-minute growth is what matters for a long shift.
	var minutes: float = maxf((last["t"] - first["t"]) / 60.0, 0.01)
	print("[SOAK] growth per minute: objects=%+.0f nodes=%+.0f mem=%+.2fMB" % [
		(last["objects"] - first["objects"]) / minutes,
		(last["nodes"] - first["nodes"]) / minutes,
		(last["mem_mb"] - first["mem_mb"]) / minutes,
	])
