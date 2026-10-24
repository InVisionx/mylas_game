class_name StoreBuilder
extends Node3D
## Builds the whole grocery store from code at load time.
##
## Everything here is cheap geometry with shared materials, so the scene stays
## a couple of hundred draw calls on mobile instead of a couple of thousand.

signal built

var nav_graph: AStar3D

var world_body: StaticBody3D
var belt: Node3D
var entrance_door: Node3D
var register_screen: Label3D
var register_body: Node3D
var security_monitor: Node3D
var stockroom_door: Node3D
var ceiling_lights: Array[Node3D] = []
var flicker_group: Array[Node3D] = []
var camera_anchors: Array[Node3D] = []
var shelf_anchor_points: Array[Vector3] = []
var spill_lights: Array[OmniLight3D] = []
var aisle_labels: Array[Label3D] = []

var _mats: Dictionary = {}
var _multimesh_root: Node3D
var _fixture_root: Node3D


func _ready() -> void:
	build()


func build() -> void:
	_make_materials()
	world_body = StaticBody3D.new()
	world_body.name = "WorldCollision"
	world_body.collision_layer = 1
	world_body.collision_mask = 0
	add_child(world_body)

	_multimesh_root = Node3D.new()
	_multimesh_root.name = "PropBatches"
	add_child(_multimesh_root)

	_fixture_root = Node3D.new()
	_fixture_root.name = "Fixtures"
	add_child(_fixture_root)

	_build_shell()
	_build_shelves()
	_build_cooler_wall()
	_build_produce()
	_build_freezer()
	_build_counter()
	_build_back_rooms()
	_build_outside()
	_build_lighting()
	_build_camera_anchors()
	_build_environment()
	nav_graph = StoreLayout.build_nav_graph()
	built.emit()


# --- Materials --------------------------------------------------------------

func _make_materials() -> void:
	_mats["floor"] = ShaderMaterial.new()
	var floor_shader := load("res://shaders/store_floor.gdshader")
	if floor_shader:
		(_mats["floor"] as ShaderMaterial).shader = floor_shader
	_mats["wall"] = _mat(Color(0.79, 0.78, 0.74))
	_mats["wall_low"] = _mat(Color(0.42, 0.45, 0.46))
	_mats["ceiling"] = _mat(Color(0.55, 0.56, 0.57), 0.95)
	_mats["shelf"] = _mat(Color(0.62, 0.63, 0.66), 0.7)
	_mats["shelf_dark"] = _mat(Color(0.32, 0.34, 0.37), 0.8)
	_mats["metal"] = _mat(Color(0.62, 0.64, 0.68), 0.35, 0.8)
	_mats["counter"] = _mat(Color(0.30, 0.33, 0.36), 0.6)
	_mats["counter_top"] = _mat(Color(0.52, 0.55, 0.57), 0.45)
	_mats["belt"] = _mat(Color(0.14, 0.15, 0.16), 0.9)
	_mats["dark"] = _mat(Color(0.10, 0.11, 0.12), 0.9)
	_mats["backroom"] = _mat(Color(0.46, 0.47, 0.46), 0.9)
	_mats["crate"] = _mat(Color(0.53, 0.40, 0.26), 0.9)
	_mats["glass"] = _glass_mat(Color(0.68, 0.80, 0.84, 0.16), 0.06)
	_mats["fridge_glass"] = _glass_mat(Color(0.72, 0.86, 0.90, 0.20), 0.06)
	_mats["fridge_light"] = _emissive(Color(0.80, 0.93, 1.0), 1.6)
	_mats["panel"] = _emissive(Color(1.0, 0.98, 0.92), 2.4)
	_mats["panel_dim"] = _emissive(Color(0.85, 0.88, 0.82), 0.9)
	_mats["red"] = _emissive(Color(1.0, 0.18, 0.14), 1.4)
	_mats["green"] = _emissive(Color(0.3, 1.0, 0.6), 1.1)
	_mats["screen"] = _mat(Color(0.04, 0.05, 0.06), 0.2)
	_mats["lot"] = _mat(Color(0.13, 0.14, 0.15), 0.95)
	_mats["asphalt_line"] = _mat(Color(0.55, 0.55, 0.5), 0.9)
	_mats["car"] = _mat(Color(0.24, 0.27, 0.31), 0.35, 0.5)
	_mats["tree"] = _mat(Color(0.07, 0.09, 0.08), 1.0)
	_mats["product"] = _product_mat()


func _mat(color: Color, roughness: float = 0.9, metallic: float = 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	return material


func _glass_mat(color: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.roughness = roughness
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material


func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


func _product_mat() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.75
	return material


# --- Primitive helpers ------------------------------------------------------

func _box(size: Vector3, position: Vector3, material: Material, collide: bool = true, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(instance)
	if collide:
		_add_collider(size, position)
	return instance


func _add_collider(size: Vector3, position: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = position
	world_body.add_child(collision)



func _quad(size: Vector2, position: Vector3, material: Material, parent: Node3D = null) -> MeshInstance3D:
	var mesh := QuadMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	(parent if parent else self).add_child(instance)
	return instance


func _label(text: String, position: Vector3, font_size: int = 64, color: Color = Color(0.92, 0.96, 1.0)) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.004
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.position = position
	label.outline_size = 6
	label.outline_modulate = Color(0, 0, 0, 0.75)
	add_child(label)
	return label


## One draw call for a pile of identical little boxes (products, stock, debris).
func _batch(size: Vector3, transforms: Array, colors: Array, parent: Node3D = null) -> MultiMeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = mesh
	multimesh.instance_count = transforms.size()
	for i in transforms.size():
		multimesh.set_instance_transform(i, transforms[i])
		multimesh.set_instance_color(i, colors[i] if i < colors.size() else Color.WHITE)
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _mats["product"]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else _multimesh_root).add_child(instance)
	return instance


# --- Store shell ------------------------------------------------------------

func _build_shell() -> void:
	var depth := StoreLayout.FRONT_Z - StoreLayout.ROOM_Z
	var mid_z := (StoreLayout.FRONT_Z + StoreLayout.ROOM_Z) * 0.5

	_box(Vector3(18.0, 0.2, depth), Vector3(0.0, -0.1, mid_z), _mats["floor"])
	_box(Vector3(18.0, 0.2, depth), Vector3(0.0, StoreLayout.CEILING + 0.1, mid_z), _mats["ceiling"])

	_box(Vector3(0.4, StoreLayout.CEILING, depth), Vector3(-9.2, StoreLayout.CEILING * 0.5, mid_z), _mats["wall"])
	_box(Vector3(0.4, StoreLayout.CEILING, depth), Vector3(9.2, StoreLayout.CEILING * 0.5, mid_z), _mats["wall"])
	_box(Vector3(0.06, 0.28, depth), Vector3(-8.98, 0.14, mid_z), _mats["wall_low"], false)
	_box(Vector3(0.06, 0.28, depth), Vector3(8.98, 0.14, mid_z), _mats["wall_low"], false)

	# Back wall between store and staff rooms, with two doorways.
	for span in [[-9.0, -5.6], [-4.4, -0.5], [0.5, 4.4], [5.6, 9.0]]:
		var x0: float = span[0]
		var x1: float = span[1]
		var width := x1 - x0
		_box(Vector3(width, StoreLayout.CEILING, 0.3),
			Vector3((x0 + x1) * 0.5, StoreLayout.CEILING * 0.5, StoreLayout.BACK_Z), _mats["wall"])
	_box(Vector3(1.2, 0.7, 0.3), Vector3(-5.0, 3.25, StoreLayout.BACK_Z), _mats["wall"], false)
	_box(Vector3(1.2, 0.7, 0.3), Vector3(5.0, 3.25, StoreLayout.BACK_Z), _mats["wall"], false)

	_build_storefront()
	var shop_sign := _label("NIGHT OWL MARKET", Vector3(0.0, 3.05, StoreLayout.FRONT_Z - 0.18), 72, Color(0.85, 0.95, 1.0))
	shop_sign.rotation.y = PI
	_box(Vector3(2.8, 0.03, 1.7), Vector3(0.0, 0.02, 11.6), _mats["dark"], false)


func _build_storefront() -> void:
	var front_z := StoreLayout.FRONT_Z
	_box(Vector3(18.0, 0.7, 0.3), Vector3(0.0, 3.25, front_z), _mats["wall"], false)
	var mullion_x := [-9.0, -6.0, -3.0, -1.35, 1.35, 3.0, 6.0, 9.0]
	for x in mullion_x:
		_box(Vector3(0.16, 3.1, 0.22), Vector3(x, 1.6, front_z), _mats["metal"])
	for i in range(mullion_x.size() - 1):
		var left: float = mullion_x[i]
		var right: float = mullion_x[i + 1]
		if left >= -1.4 and right <= 1.4:
			continue
		var width := (right - left) - 0.16
		var centre := (left + right) * 0.5
		var pane := _box(Vector3(width, 2.95, 0.06), Vector3(centre, 1.6, front_z), _mats["glass"], false)
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_add_collider(Vector3(width, 3.0, 0.3), Vector3(centre, 1.5, front_z))
	_box(Vector3(2.7, 0.1, 0.3), Vector3(0.0, 0.05, front_z), _mats["metal"], false)

	entrance_door = Node3D.new()
	entrance_door.name = "EntranceDoors"
	entrance_door.position = Vector3(0.0, 0.0, front_z)
	add_child(entrance_door)
	for side in [-1, 1]:
		var panel := Node3D.new()
		panel.name = "PanelLeft" if side < 0 else "PanelRight"
		panel.position = Vector3(side * 0.68, 0.0, 0.0)
		entrance_door.add_child(panel)
		var glass := _box(Vector3(1.3, 2.9, 0.06), Vector3(0.0, 1.55, 0.0), _mats["glass"], false, panel)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(Vector3(1.34, 0.10, 0.10), Vector3(0.0, 2.98, 0.0), _mats["metal"], false, panel)
		_box(Vector3(1.34, 0.10, 0.10), Vector3(0.0, 0.12, 0.0), _mats["metal"], false, panel)
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.3, 2.9, 0.2)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(0.0, 1.55, 0.0)
		panel.add_child(collision)
		panel.set_meta("closed_x", panel.position.x)

	for i in 3:
		_box(Vector3(0.5, 0.42, 0.6), Vector3(-2.4 + i * 0.08, 0.22 + i * 0.02, 11.2), _mats["metal"], false)
	_box(Vector3(0.62, 0.9, 1.6), Vector3(3.6, 0.46, 11.4), _mats["metal"], true)
	_box(Vector3(0.62, 0.9, 1.6), Vector3(4.4, 0.46, 11.4), _mats["metal"], true)


func open_entrance(open: bool) -> void:
	if entrance_door == null:
		return
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	for panel in entrance_door.get_children():
		var closed_x: float = panel.get_meta("closed_x", 0.0)
		var target_x := closed_x * (2.15 if open else 1.0)
		tween.tween_property(panel, "position:x", target_x, 0.55)


# --- Aisles -----------------------------------------------------------------

func _build_shelves() -> void:
	var palette := _product_palette()
	for shelf in StoreLayout.SHELVES:
		var x: float = shelf["x"]
		var z0: float = shelf["z0"]
		var z1: float = shelf["z1"]
		var length := z1 - z0
		var centre_z := (z0 + z1) * 0.5

		_box(Vector3(1.24, 0.20, length), Vector3(x, 0.10, centre_z), _mats["shelf_dark"])
		_box(Vector3(0.10, 1.95, length), Vector3(x, 0.98, centre_z), _mats["shelf_dark"])
		for height in [0.55, 1.05, 1.55]:
			_box(Vector3(1.14, 0.06, length), Vector3(x, height, centre_z), _mats["shelf"])
		_box(Vector3(1.24, 1.95, 0.08), Vector3(x, 0.98, z0 + 0.04), _mats["shelf"])
		_box(Vector3(1.24, 1.95, 0.08), Vector3(x, 0.98, z1 - 0.04), _mats["shelf"])
		_box(Vector3(1.30, 0.16, length), Vector3(x, 2.02, centre_z), _mats["shelf_dark"], false)

		var transforms: Array = []
		var colors: Array = []
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(shelf["id"])
		for side in [-1.0, 1.0]:
			for row_y in [0.72, 1.22, 1.72]:
				var z := z0 + 0.35
				while z < z1 - 0.30:
					var jitter := rng.randf_range(-0.02, 0.02)
					var scale_y := rng.randf_range(0.85, 1.15)
					var basis := Basis(Vector3.UP, rng.randf_range(-0.06, 0.06)).scaled(Vector3(1.0, scale_y, 1.0))
					transforms.append(Transform3D(basis, Vector3(x + side * 0.38, row_y + jitter, z)))
					colors.append(palette[rng.randi_range(0, palette.size() - 1)])
					if rng.randf() < 0.10:
						z += 0.30
					z += 0.27
		_batch(Vector3(0.22, 0.30, 0.18), transforms, colors)

		var label := _label(shelf["label"], Vector3(x, 2.28, z1 + 0.05), 56, Color(0.95, 0.97, 1.0))
		aisle_labels.append(label)

		shelf_anchor_points.append(Vector3(x + 1.1, 0.0, (z0 + z1) * 0.5))
		shelf_anchor_points.append(Vector3(x - 1.1, 0.0, (z0 + z1) * 0.5))


func _product_palette() -> Array:
	var palette: Array = []
	for product in GameData.products:
		palette.append(Color.html(str(product.get("color", "#cccccc")).replace("#", "")))
	if palette.is_empty():
		palette.append(Color(0.7, 0.3, 0.3))
	return palette


func _build_cooler_wall() -> void:
	var rect := StoreLayout.FRIDGE_RECT
	var x_front := rect.position.x
	var z0 := rect.position.y
	var z1 := rect.position.y + rect.size.y
	var length := z1 - z0
	var centre_z := (z0 + z1) * 0.5

	_box(Vector3(0.55, 2.6, length), Vector3(x_front + 0.32, 1.3, centre_z), _mats["metal"])
	_box(Vector3(0.06, 2.3, length - 0.3), Vector3(x_front + 0.58, 1.35, centre_z), _mats["fridge_light"], false)
	for height in [0.55, 1.05, 1.55, 2.05]:
		_box(Vector3(0.5, 0.05, length - 0.3), Vector3(x_front + 0.35, height, centre_z), _mats["shelf"], false)

	var bays := 6
	var bay_width := length / float(bays)
	for b in bays:
		var z := z0 + bay_width * (b + 0.5)
		_box(Vector3(0.05, 2.5, 0.08), Vector3(x_front + 0.02, 1.3, z - bay_width * 0.5 + 0.04), _mats["metal"], false)
		var glass := _box(Vector3(0.05, 2.2, bay_width - 0.12), Vector3(x_front + 0.02, 1.35, z), _mats["fridge_glass"], false)
		glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box(Vector3(0.07, 0.6, 0.05), Vector3(x_front - 0.02, 1.25, z + bay_width * 0.35), _mats["metal"], false)

	var transforms: Array = []
	var colors: Array = []
	var palette := _product_palette()
	var rng := RandomNumberGenerator.new()
	rng.seed = 771
	for height in [0.72, 1.22, 1.72, 2.2]:
		var z := z0 + 0.25
		while z < z1 - 0.25:
			transforms.append(Transform3D(Basis.IDENTITY, Vector3(x_front + 0.3, height, z)))
			colors.append(palette[rng.randi_range(0, palette.size() - 1)].lerp(Color(0.8, 0.9, 1.0), 0.35))
			z += 0.26
	_batch(Vector3(0.24, 0.28, 0.18), transforms, colors)

	var sign_label := _label("DAIRY  ·  CHILLED", Vector3(x_front - 0.1, 2.85, centre_z), 60, Color(0.75, 0.92, 1.0))
	sign_label.rotation.y = -PI * 0.5

	for i in 3:
		var light := OmniLight3D.new()
		light.position = Vector3(x_front - 0.9, 2.3, z0 + length * (0.2 + i * 0.3))
		light.light_color = Color(0.6, 0.82, 1.0)
		light.light_energy = 0.85
		light.omni_range = 5.5
		light.shadow_enabled = false
		add_child(light)
		light.add_to_group("ambience_lights")
		spill_lights.append(light)


func _build_produce() -> void:
	var rect := StoreLayout.PRODUCE_RECT
	var centre := Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	for i in 2:
		var z := rect.position.y + 0.5 + i * 0.95
		_box(Vector3(rect.size.x, 0.55, 0.85), Vector3(centre.x, 0.28, z), _mats["crate"])
		_box(Vector3(rect.size.x - 0.2, 0.10, 0.65), Vector3(centre.x, 0.57, z), _mats["crate"], false)

	var sphere := SphereMesh.new()
	sphere.radius = 0.075
	sphere.height = 0.15
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.mesh = sphere
	var positions: Array = []
	var colors: Array = []
	var produce_colors := [Color(0.72, 0.20, 0.16), Color(0.88, 0.74, 0.18), Color(0.42, 0.62, 0.24), Color(0.86, 0.48, 0.16)]
	for i in 2:
		var z := rect.position.y + 0.5 + i * 0.95
		for row in 2:
			for col in 9:
				positions.append(Vector3(centre.x - 1.4 + col * 0.34, 0.66 + row * 0.02, z - 0.16 + row * 0.30))
				colors.append(produce_colors[(col + row + i) % produce_colors.size()])
	multimesh.instance_count = positions.size()
	for i in positions.size():
		multimesh.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
		multimesh.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _mats["product"]
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)

	_label("PRODUCE", Vector3(centre.x, 1.55, rect.position.y + rect.size.y), 60, Color(0.85, 1.0, 0.85))


func _build_freezer() -> void:
	var rect := StoreLayout.FREEZER_RECT
	var centre := Vector3(rect.position.x + rect.size.x * 0.5, 0.0, rect.position.y + rect.size.y * 0.5)
	_box(Vector3(rect.size.x, 0.9, rect.size.y), Vector3(centre.x, 0.45, centre.z), _mats["metal"])
	_box(Vector3(rect.size.x - 0.2, 0.06, rect.size.y - 0.2), Vector3(centre.x, 0.92, centre.z), _mats["fridge_light"], false)
	for side in [-1.0, 1.0]:
		var lid := _box(Vector3(rect.size.x * 0.47, 0.04, rect.size.y - 0.1), Vector3(centre.x + side * rect.size.x * 0.245, 0.95, centre.z), _mats["fridge_glass"], false)
		lid.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label("FROZEN", Vector3(centre.x, 2.35, centre.z + 0.2), 60, Color(0.8, 0.95, 1.0))

	var light := OmniLight3D.new()
	light.position = Vector3(centre.x, 2.0, centre.z + 0.8)
	light.light_color = Color(0.65, 0.85, 1.0)
	light.light_energy = 0.5
	light.omni_range = 5.0
	light.shadow_enabled = false
	add_child(light)
	light.add_to_group("ambience_lights")
	spill_lights.append(light)


# --- Checkout ---------------------------------------------------------------

func _build_counter() -> void:
	var counter_z := 7.9
	_box(Vector3(4.6, 0.92, 0.86), Vector3(0.6, 0.46, counter_z), _mats["counter"])
	_box(Vector3(4.7, 0.07, 0.98), Vector3(0.6, 1.0, counter_z), _mats["counter_top"], false)
	_box(Vector3(4.6, 0.12, 0.10), Vector3(0.6, 0.06, counter_z + 0.40), _mats["dark"], false)

	_box(Vector3(2.9, 0.05, 0.54), Vector3(-0.1, 1.045, counter_z), _mats["belt"], false)
	_box(Vector3(2.9, 0.08, 0.05), Vector3(-0.1, 1.06, counter_z - 0.30), _mats["metal"], false)
	_box(Vector3(2.9, 0.08, 0.05), Vector3(-0.1, 1.06, counter_z + 0.30), _mats["metal"], false)
	belt = Node3D.new()
	belt.name = "Belt"
	belt.position = Vector3(-1.35, 1.08, counter_z)
	add_child(belt)

	_box(Vector3(0.46, 0.16, 0.52), Vector3(1.62, 1.09, counter_z), _mats["dark"], false)
	_box(Vector3(0.40, 0.02, 0.44), Vector3(1.62, 1.18, counter_z), _mats["red"], false)
	_box(Vector3(0.10, 0.22, 0.10), Vector3(1.62, 1.30, counter_z - 0.16), _mats["metal"], false)

	register_body = Node3D.new()
	register_body.name = "Register"
	register_body.position = Vector3(2.35, 0.0, counter_z)
	add_child(register_body)
	_box(Vector3(0.56, 0.34, 0.42), Vector3(0.0, 1.20, 0.0), _mats["dark"], false, register_body)
	_box(Vector3(0.16, 0.20, 0.16), Vector3(0.0, 1.42, -0.04), _mats["metal"], false, register_body)
	var screen := _box(Vector3(0.52, 0.34, 0.04), Vector3(0.0, 1.58, 0.10), _mats["screen"], false, register_body)
	screen.rotation.x = deg_to_rad(-12.0)
	register_screen = Label3D.new()
	register_screen.name = "RegisterScreenText"
	register_screen.text = "TOTAL $0.00"
	register_screen.font_size = 42
	register_screen.pixel_size = 0.0016
	register_screen.modulate = Color(0.55, 1.0, 0.72)
	register_screen.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	register_screen.outline_size = 0
	register_screen.position = Vector3(0.0, 1.58, 0.13)
	register_screen.rotation.x = deg_to_rad(-12.0)
	register_body.add_child(register_screen)

	_box(Vector3(0.28, 0.20, 0.24), Vector3(2.72, 1.13, counter_z + 0.32), _mats["dark"], false)
	_box(Vector3(0.16, 0.10, 0.16), Vector3(1.95, 1.09, counter_z + 0.36), _mats["metal"], false)

	# Security monitor on a post at the left end of the counter.
	security_monitor = Node3D.new()
	security_monitor.name = "SecurityMonitor"
	security_monitor.position = Vector3(-2.05, 0.0, 8.55)
	add_child(security_monitor)
	_box(Vector3(0.10, 1.35, 0.10), Vector3(0.0, 0.67, 0.0), _mats["metal"], true, security_monitor)
	var monitor_body := _box(Vector3(0.62, 0.44, 0.16), Vector3(0.0, 1.5, 0.0), _mats["dark"], false, security_monitor)
	monitor_body.rotation.y = deg_to_rad(-22.0)
	var monitor_screen := _box(Vector3(0.54, 0.36, 0.02), Vector3(0.0, 1.5, 0.09), _mats["screen"], false, security_monitor)
	monitor_screen.name = "Screen"
	monitor_screen.rotation.y = deg_to_rad(-22.0)

	_box(Vector3(1.1, 1.1, 0.3), Vector3(3.5, 0.55, 6.9), _mats["shelf_dark"])
	_box(Vector3(1.0, 0.04, 0.26), Vector3(3.5, 0.92, 6.9), _mats["metal"], false)

	_label("CHECKOUT 1", Vector3(0.6, 2.62, counter_z), 60, Color(1.0, 0.95, 0.8))

	var lamp := OmniLight3D.new()
	lamp.position = Vector3(2.1, 2.05, 8.7)
	lamp.light_color = Color(1.0, 0.86, 0.68)
	lamp.light_energy = 0.9
	lamp.omni_range = 4.2
	lamp.shadow_enabled = false
	add_child(lamp)
	lamp.add_to_group("ambience_lights")
	spill_lights.append(lamp)


func set_register_text(text: String, color: Color = Color(0.55, 1.0, 0.72)) -> void:
	if register_screen == null:
		return
	register_screen.text = text
	register_screen.modulate = color


# --- Staff rooms ------------------------------------------------------------

func _build_back_rooms() -> void:
	_box(Vector3(0.3, StoreLayout.CEILING, 6.0), Vector3(0.0, StoreLayout.CEILING * 0.5, -11.0), _mats["backroom"])
	_box(Vector3(18.0, StoreLayout.CEILING, 0.3), Vector3(0.0, StoreLayout.CEILING * 0.5, StoreLayout.ROOM_Z), _mats["backroom"])

	# Stockroom, left of the divider.
	_box(Vector3(0.25, 2.4, 4.5), Vector3(-8.85, 1.2, -11.2), _mats["shelf_dark"])
	for h in [0.6, 1.2, 1.8]:
		_box(Vector3(0.9, 0.06, 4.4), Vector3(-8.4, h, -11.2), _mats["shelf"], false)
	var crates: Array = []
	var crate_colors: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in 14:
		var px := rng.randf_range(-7.6, -1.2)
		var pz := rng.randf_range(-13.4, -9.0)
		var stack := rng.randi_range(1, 3)
		for s in stack:
			crates.append(Transform3D(Basis.IDENTITY, Vector3(px, 0.26 + s * 0.5, pz)))
			crate_colors.append(Color(0.52, 0.40, 0.28).lerp(Color(0.42, 0.35, 0.26), rng.randf()))
	_batch(Vector3(0.66, 0.5, 0.58), crates, crate_colors)

	# Desk + dead monitor in the corner of the stockroom.
	_box(Vector3(1.6, 0.08, 0.8), Vector3(-3.2, 0.74, -12.9), _mats["counter_top"])
	_box(Vector3(0.1, 0.74, 0.7), Vector3(-2.5, 0.37, -12.9), _mats["dark"], false)
	_box(Vector3(0.1, 0.74, 0.7), Vector3(-3.9, 0.37, -12.9), _mats["dark"], false)
	_box(Vector3(0.5, 0.38, 0.06), Vector3(-3.2, 1.0, -12.95), _mats["screen"], false)
	_box(Vector3(0.5, 0.05, 0.2), Vector3(-3.2, 0.79, -12.85), _mats["dark"], false)

	# Break room, right of the divider: table, chairs, lockers, vending machine.
	_box(Vector3(1.8, 0.07, 1.1), Vector3(4.2, 0.76, -11.0), _mats["counter_top"])
	for leg in [Vector3(3.4, 0.38, -10.5), Vector3(5.0, 0.38, -10.5), Vector3(3.4, 0.38, -11.5), Vector3(5.0, 0.38, -11.5)]:
		_box(Vector3(0.08, 0.76, 0.08), leg, _mats["metal"], false)
	for chair_pos in [Vector3(4.2, 0.0, -10.1), Vector3(4.2, 0.0, -11.9)]:
		_box(Vector3(0.5, 0.06, 0.5), chair_pos + Vector3(0, 0.45, 0), _mats["dark"], false)
		_box(Vector3(0.5, 0.5, 0.06), chair_pos + Vector3(0, 0.72, -0.22), _mats["dark"], false)
		for lx in [-0.2, 0.2]:
			for lz in [-0.2, 0.2]:
				_box(Vector3(0.05, 0.45, 0.05), chair_pos + Vector3(lx, 0.22, lz), _mats["metal"], false)
	_box(Vector3(1.2, 2.0, 0.55), Vector3(7.9, 1.0, -12.4), _mats["metal"])
	for i in 3:
		_box(Vector3(0.04, 1.8, 0.5), Vector3(7.55 + i * 0.35, 1.0, -12.4), _mats["dark"], false)
	_box(Vector3(0.9, 1.9, 0.7), Vector3(2.0, 0.95, -13.3), _mats["counter"])
	_box(Vector3(0.7, 1.2, 0.03), Vector3(2.0, 1.1, -12.94), _mats["fridge_light"], false)
	_label("BREAK ROOM", Vector3(4.5, 2.9, StoreLayout.BACK_Z + 0.2), 52, Color(0.9, 0.92, 0.95))
	_label("STOCKROOM", Vector3(-5.0, 3.0, StoreLayout.BACK_Z + 0.2), 52, Color(0.9, 0.92, 0.95))

	# Staff doors (closed at shift start, they can open on their own later).
	stockroom_door = _make_door(Vector3(-5.0, 0.0, StoreLayout.BACK_Z + 0.05), -1.0)
	_make_door(Vector3(5.0, 0.0, StoreLayout.BACK_Z + 0.05), 1.0)

	for room_x in [-4.5, 4.5]:
		var light := OmniLight3D.new()
		light.position = Vector3(room_x, 2.9, -11.0)
		light.light_color = Color(0.95, 0.93, 0.82)
		light.light_energy = 0.55
		light.omni_range = 6.5
		light.shadow_enabled = false
		add_child(light)
		light.add_to_group("ambience_lights")
		flicker_group.append(light)


func _make_door(position: Vector3, hinge_side: float) -> Node3D:
	var frame := Node3D.new()
	frame.position = position
	add_child(frame)
	_box(Vector3(1.3, 2.2, 0.12), Vector3(0, 1.1, 0), _mats["dark"], false, frame)
	var pivot := StaticBody3D.new()
	pivot.name = "DoorPivot"
	pivot.position = Vector3(hinge_side * 0.55, 0.0, 0.0)
	pivot.collision_layer = 1 | 8
	pivot.collision_mask = 0
	frame.add_child(pivot)
	var slab := _box(Vector3(1.08, 2.08, 0.07), Vector3(-hinge_side * 0.54, 1.04, 0.0), _mats["metal"], false, pivot)
	slab.name = "Slab"
	_box(Vector3(0.06, 0.06, 0.24), Vector3(-hinge_side * 0.92, 1.0, 0.0), _mats["dark"], false, pivot)
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.1, 2.1, 0.12)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(-hinge_side * 0.54, 1.04, 0.0)
	pivot.add_child(collision)
	var script := load("res://scripts/world/staff_door.gd")
	if script:
		pivot.set_script(script)
		pivot.set("open_angle", deg_to_rad(94.0) * -hinge_side)
	return pivot


# --- Outside ----------------------------------------------------------------

func _build_outside() -> void:
	_box(Vector3(64.0, 0.1, 34.0), Vector3(0.0, -0.06, 30.0), _mats["lot"], false)
	_box(Vector3(64.0, 0.18, 0.8), Vector3(0.0, 0.02, 13.5), _mats["wall_low"], false)
	# Ground collider so shoppers can walk in from the lot.
	_add_collider(Vector3(64.0, 0.4, 34.0), Vector3(0.0, -0.22, 30.0))

	for i in 9:
		var x := -16.0 + i * 4.0
		_box(Vector3(0.12, 0.02, 5.0), Vector3(x, 0.02, 22.0), _mats["asphalt_line"], false)

	# Parked cars
	for car in [[-11.0, 20.0, 0.0], [8.5, 24.5, PI], [-3.0, 27.0, PI * 0.5]]:
		var car_pos := Vector3(car[0], 0.0, car[1])
		var car_rot: float = car[2]
		var body := _box(Vector3(1.9, 0.7, 4.2), car_pos + Vector3(0, 0.55, 0), _mats["car"], false)
		body.rotation.y = car_rot
		var cabin := _box(Vector3(1.7, 0.55, 2.1), car_pos + Vector3(0, 1.05, -0.2), _mats["dark"], false)
		cabin.rotation.y = car_rot
		for wheel in [Vector3(-0.95, 0.3, 1.3), Vector3(0.95, 0.3, 1.3), Vector3(-0.95, 0.3, -1.3), Vector3(0.95, 0.3, -1.3)]:
			var wheel_pos: Vector3 = car_pos + wheel
			_box(Vector3(0.22, 0.6, 0.6), wheel_pos, _mats["dark"], false)

	# Light poles with cold sodium lamps
	for i in 3:
		var pole_pos := Vector3(-14.0 + i * 14.0, 0.0, 18.0)
		_box(Vector3(0.18, 6.0, 0.18), pole_pos + Vector3(0, 3.0, 0), _mats["metal"], false)
		_box(Vector3(1.1, 0.16, 0.5), pole_pos + Vector3(0, 6.0, 0), _mats["panel_dim"], false)
		var pole_light := OmniLight3D.new()
		pole_light.position = pole_pos + Vector3(0, 5.7, 0)
		pole_light.light_color = Color(0.85, 0.88, 1.0)
		pole_light.light_energy = 1.6
		pole_light.omni_range = 15.0
		pole_light.shadow_enabled = false
		add_child(pole_light)
		pole_light.add_to_group("ambience_lights")

	# Dark treeline and a distant neighbour building
	for i in 12:
		_box(Vector3(4.0, 7.0 + (i % 3) * 2.0, 3.0), Vector3(-30.0 + i * 5.5, 2.5, 44.0), _mats["tree"], false)
	_box(Vector3(14.0, 9.0, 8.0), Vector3(-24.0, 4.0, 38.0), _mats["tree"], false)
	_box(Vector3(9.0, 12.0, 9.0), Vector3(26.0, 5.5, 39.0), _mats["tree"], false)


# --- Lighting ---------------------------------------------------------------

func _build_lighting() -> void:
	var panel_x := [-6.4, -2.2, 2.2, 6.4]
	var panel_z := [-5.4, -1.4, 2.6, 6.6, 10.4]
	var light_spots: Array = []
	for z in panel_z:
		for x in panel_x:
			var panel := _box(Vector3(2.1, 0.10, 0.75), Vector3(x, StoreLayout.CEILING - 0.06, z), _mats["panel"], false)
			panel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			light_spots.append([Vector3(x, StoreLayout.CEILING - 0.3, z), panel])

	# Only every other panel gets a real light; the rest are pure emission.
	var idx := 0
	for spot in light_spots:
		idx += 1
		if idx % 2 == 0:
			continue
		var light := OmniLight3D.new()
		light.position = spot[0]
		light.light_color = Color(0.93, 0.96, 0.9)
		light.light_energy = 1.15
		light.omni_range = 8.5
		light.omni_attenuation = 1.2
		light.shadow_enabled = false
		light.set_meta("panel", spot[1])
		add_child(light)
		ceiling_lights.append(light)
		flicker_group.append(light)

	# Exit sign above the doors
	_box(Vector3(0.7, 0.26, 0.05), Vector3(0.0, 2.7, StoreLayout.FRONT_Z - 0.14), _mats["red"], false)
	var exit_sign := _label("EXIT", Vector3(0.0, 2.7, StoreLayout.FRONT_Z - 0.22), 40, Color(1.0, 0.5, 0.45))
	exit_sign.rotation.y = PI


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.015, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.42, 0.52)
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.10, 0.12, 0.16)
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0
	env.glow_enabled = false
	env.ssao_enabled = false
	world_env.environment = env
	add_child(world_env)


func _build_camera_anchors() -> void:
	for feed in StoreLayout.CAMERA_FEEDS:
		var anchor := Node3D.new()
		anchor.name = "Cam_%s" % feed["id"]
		anchor.position = feed["pos"]
		add_child(anchor)
		anchor.look_at(feed["look"], Vector3.UP)
		camera_anchors.append(anchor)

		# Visible dome so the cameras feel like part of the store.
		_box(Vector3(0.22, 0.18, 0.34), Vector3(0.0, 0.0, 0.02), _mats["dark"], false, anchor)
		var lens := MeshInstance3D.new()
		var lens_mesh := CylinderMesh.new()
		lens_mesh.top_radius = 0.07
		lens_mesh.bottom_radius = 0.07
		lens_mesh.height = 0.08
		lens_mesh.radial_segments = 10
		lens.mesh = lens_mesh
		lens.material_override = _mats["screen"]
		lens.position = Vector3(0.0, 0.0, -0.19)
		lens.rotation.x = PI * 0.5
		lens.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		anchor.add_child(lens)
		_box(Vector3(0.035, 0.035, 0.02), Vector3(0.09, 0.06, -0.16), _mats["red"], false, anchor)
