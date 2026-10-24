class_name ProductItem
extends Node3D
## A single grocery item: belt prop, collider, price and scan state.

var data: Dictionary = {}
var price: int = 0
var is_impossible: bool = false
var scanned: bool = false
var belt_index: int = 0
var inspected: bool = false
var anomaly_note: String = ""

var _body: StaticBody3D
var _visual: Node3D


func setup(product: Dictionary, impossible: bool = false) -> void:
	data = product
	is_impossible = impossible
	price = int(product.get("price", 0))
	if impossible:
		anomaly_note = str(product.get("note", "It is not food."))
	name = "Item_%s" % str(product.get("id", "unknown"))

	_visual = ProductMesh.build(product)
	_visual.name = "Visual"
	add_child(_visual)

	_body = StaticBody3D.new()
	_body.collision_layer = 16
	_body.collision_mask = 0
	add_child(_body)
	var shape := BoxShape3D.new()
	var size_data: Array = product.get("size", [0.2, 0.2, 0.15])
	var s := Vector3(0.2, 0.2, 0.15)
	if size_data.size() >= 3:
		s = Vector3(float(size_data[0]), float(size_data[1]), float(size_data[2]))
	shape.size = s * 1.05
	var collision := CollisionShape3D.new()
	collision.shape = shape
	_body.add_child(collision)
	_body.set_meta("item", self)


func get_interact_prompt() -> String:
	if scanned:
		return "%s  ·  scanned" % str(data.get("name", "Item"))
	return "SCAN  %s" % str(data.get("name", "Item"))


func interact(player: Node = null) -> void:
	var manager := _find_checkout()
	if manager != null:
		manager.call("scan_item", self, player)


func _find_checkout() -> Node:
	var node := get_parent()
	while node != null:
		if node.has_method("scan_item"):
			return node
		node = node.get_parent()
	return null


func item_size() -> Vector3:
	var size_data: Array = data.get("size", [0.2, 0.2, 0.15])
	if size_data.size() < 3:
		return Vector3(0.2, 0.2, 0.15)
	return Vector3(float(size_data[0]), float(size_data[1]), float(size_data[2]))


func note_text() -> String:
	if not anomaly_note.is_empty():
		return anomaly_note
	return str(data.get("note", ""))
