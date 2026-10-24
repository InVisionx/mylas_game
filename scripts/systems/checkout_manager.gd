class_name CheckoutManager
extends Node3D
## Owns the belt, the scanner and the running total.
##
## Scanning is deliberately forgiving: aim at an item and press interact and it
## slides to the scanner by itself. No pixel-perfect dragging on a handheld.

signal basket_loaded(customer: Customer)
signal scan_progress(scanned: int, total: int)
signal all_scanned()
signal anomaly_flagged(anomaly_id: String)

var builder: StoreBuilder
var customer: Customer = null
var items: Array[ProductItem] = []
var scanned_count := 0
var total_cents := 0
var active := false
var checkout_ready := false

var _scanning := false
var _barcode_flagged := false

const SCAN_POINT := Vector3(1.62, 1.16, 7.9)
const BELT_START := Vector3(-1.15, 0.0, 7.9)
const BELT_STEP := 0.34


func _ready() -> void:
	add_to_group("checkout")


func setup(store_builder: StoreBuilder) -> void:
	builder = store_builder
	_clear_belt()


func _clear_belt() -> void:
	for item in items:
		if is_instance_valid(item):
			item.queue_free()
	items.clear()
	scanned_count = 0
	total_cents = 0
	checkout_ready = false
	_scanning = false
	_barcode_flagged = false
	if builder:
		builder.set_register_text("TOTAL $0.00")


func begin_customer(new_customer: Customer) -> void:
	_clear_belt()
	customer = new_customer
	active = true
	await get_tree().create_timer(0.25).timeout
	if customer == null or not is_instance_valid(customer):
		return
	var index := 0
	for product in customer.basket:
		_spawn_item(product, index)
		index += 1
		await get_tree().create_timer(0.16).timeout
		if customer == null or not is_instance_valid(customer):
			return
	basket_loaded.emit(customer)
	scan_progress.emit(scanned_count, items.size())
	if builder:
		builder.set_register_text("ITEMS %d" % items.size())


func _spawn_item(product: Dictionary, index: int) -> void:
	var item := ProductItem.new()
	var impossible := int(product.get("price", 0)) == 0 and str(product.get("category", "")) == "unknown"
	add_child(item)
	item.setup(product, impossible)
	var size := item.item_size()
	var x := BELT_START.x + index * BELT_STEP
	item.position = Vector3(x, 1.09 + size.y * 0.5, BELT_START.z + 0.55)
	item.belt_index = index
	var tween := create_tween()
	tween.tween_property(item, "position:z", BELT_START.z, 0.35).set_trans(Tween.TRANS_SINE)
	items.append(item)
	Events.item_placed_on_belt.emit(item)
	AudioManager.play_at("product_fall", item.global_position, -26.0, 1.35)
	if customer != null and is_instance_valid(customer.body):
		customer.body.raise_arm("right")


func scan_item(item: ProductItem, _player: Node = null) -> void:
	if not active or item == null or not is_instance_valid(item):
		return
	if item.scanned or _scanning:
		return
	_scanning = true
	item.scanned = true

	var target := SCAN_POINT
	target.y = 1.12
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "position", target, 0.24)
	await tween.finished
	if not is_instance_valid(item):
		_scanning = false
		return

	if item.is_impossible:
		AudioManager.play("scan_fail", -4.0)
		_show_register("ERR // ITEM NOT IN SYSTEM", Color(1.0, 0.35, 0.3))
		Events.scan_failed.emit("That item is not in the system.")
		_flag_anomaly("extra_item")
		await get_tree().create_timer(0.55).timeout
	else:
		AudioManager.play("scan_ok", -8.0)
		total_cents += item.price
		scanned_count += 1
		_show_register(display_total())
		_spawn_price_popup(item.global_position, item.price)
		Events.item_scanned.emit(item, item.price)
		GameManager.session["scans"] = int(GameManager.session.get("scans", 0)) + 1
		_maybe_barcode_anomaly()
		await get_tree().create_timer(0.1).timeout

	if is_instance_valid(item):
		var exit_tween := create_tween()
		exit_tween.set_parallel(true)
		exit_tween.tween_property(item, "position", Vector3(2.45, 1.02, 8.75), 0.4)
		exit_tween.tween_property(item, "rotation:y", deg_to_rad(140.0), 0.4)
		exit_tween.chain().tween_callback(item.queue_free)
		items.erase(item)

	_scanning = false
	scan_progress.emit(scanned_count, scanned_count + _remaining_items())

	if _remaining_items() == 0 and not checkout_ready:
		checkout_ready = true
		_show_register("TOTAL %s" % GameData.price_string(total_cents))
		AudioManager.play("register_open", -14.0)
		all_scanned.emit()
		Events.checkout_ready.emit()


func _remaining_items() -> int:
	var count := 0
	for item in items:
		if is_instance_valid(item) and not item.scanned:
			count += 1
	return count


func remaining_items() -> int:
	return _remaining_items()


func _maybe_barcode_anomaly() -> void:
	if customer == null or _barcode_flagged:
		return
	if not customer.has_anomaly("barcode_text"):
		return
	if scanned_count < 2:
		return
	_barcode_flagged = true
	_show_register("Y O U   A R E   S E E N", Color(1.0, 0.3, 0.3))
	Events.register_anomaly.emit("barcode_text", { "text": "Y O U   A R E   S E E N" })
	var player := get_tree().get_first_node_in_group("player") as PlayerController
	if player != null and builder != null and builder.register_body != null:
		var to_register := (builder.register_body.global_position - player.camera.global_position).normalized()
		var forward := -player.camera.global_transform.basis.z
		if forward.dot(to_register) > 0.5:
			_flag_anomaly("barcode_text")


func _flag_anomaly(anomaly_id: String) -> void:
	if customer == null or not is_instance_valid(customer):
		return
	for anomaly in customer.anomalies:
		if str(anomaly.get("id", "")) == anomaly_id:
			customer.reveal_clue(anomaly)
			anomaly_flagged.emit(anomaly_id)
			break


func scan_all() -> void:
	if not active:
		return
	var pending: Array[ProductItem] = []
	for item in items:
		if is_instance_valid(item) and not item.scanned:
			pending.append(item)
	for item in pending:
		scan_item(item)
		await get_tree().create_timer(0.14).timeout


func _show_register(text: String, color: Color = Color(0.55, 1.0, 0.72)) -> void:
	if builder:
		builder.set_register_text(text, color)


func display_total() -> String:
	return "TOTAL %s" % GameData.price_string(total_cents)


func _spawn_price_popup(world_position: Vector3, price: int) -> void:
	var label := Label3D.new()
	label.text = "+%s" % GameData.price_string(price)
	label.font_size = 48
	label.pixel_size = 0.0022
	label.modulate = Color(0.7, 1.0, 0.8)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_size = 5
	label.outline_modulate = Color(0, 0, 0, 0.7)
	add_child(label)
	label.global_position = world_position + Vector3(0, 0.28, 0.1)
	var start_y := label.global_position.y
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "global_position:y", start_y + 0.35, 0.7)
	tween.tween_property(label, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(label.queue_free)


func finish_transaction() -> void:
	active = false
	customer = null
	_clear_belt()


func is_ready_for_decision() -> bool:
	return checkout_ready and _remaining_items() == 0


func item_count() -> int:
	return items.size()
