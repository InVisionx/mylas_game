class_name ProductMesh
extends RefCounted
## Builds a readable low-poly prop from a product data entry.
## If a real model exists at res://models/products/<id>.glb it is used instead,
## scaled to the size declared in data/products.json.
## Shapes are deliberately toy-like: distinctive silhouettes beat detail.

const MODEL_DIR := "res://models/products/"

static func build(product: Dictionary, material: Material = null) -> Node3D:
	var model := _try_model(product)
	if model != null:
		return model
	var root := Node3D.new()
	var size := _size_of(product)
	var color := _color_of(product)
	var shape := str(product.get("shape", "box"))
	var mat := material if material else _matte(color)

	match shape:
		"can":
			root.add_child(_cylinder(size.x * 0.5, size.y, mat))
			root.add_child(_box(Vector3(size.x * 1.02, size.y * 0.34, size.z * 1.02),
				Vector3(0, size.y * 0.06, 0), _matte(color.lightened(0.35))))
		"bottle":
			root.add_child(_cylinder(size.x * 0.46, size.y * 0.72, mat, Vector3(0, -size.y * 0.14, 0)))
			root.add_child(_cylinder(size.x * 0.22, size.y * 0.20, mat, Vector3(0, size.y * 0.30, 0)))
			root.add_child(_cylinder(size.x * 0.24, size.y * 0.06, _matte(color.darkened(0.35)), Vector3(0, size.y * 0.43, 0)))
			root.add_child(_box(Vector3(size.x * 0.94, size.y * 0.22, size.z * 0.94),
				Vector3(0, -size.y * 0.12, 0), _matte(Color(0.93, 0.94, 0.9))))
		"jar":
			root.add_child(_cylinder(size.x * 0.5, size.y * 0.82, mat))
			root.add_child(_cylinder(size.x * 0.52, size.y * 0.12, _matte(color.darkened(0.4)), Vector3(0, size.y * 0.44, 0)))
		"carton":
			root.add_child(_box(Vector3(size.x, size.y * 0.8, size.z), Vector3(0, -size.y * 0.08, 0), mat))
			var gable := _box(Vector3(size.x * 0.72, size.y * 0.22, size.z), Vector3(0, size.y * 0.42, 0), mat)
			gable.rotation.y = deg_to_rad(45.0)
			root.add_child(gable)
		"bag":
			root.add_child(_box(Vector3(size.x, size.y, size.z * 0.72), Vector3.ZERO, mat))
			root.add_child(_box(Vector3(size.x * 0.98, size.y * 0.18, size.z * 0.66),
				Vector3(0, size.y * 0.30, 0), _matte(color.darkened(0.3))))
		"bunch":
			var count := 4
			for i in count:
				var sphere := SphereMesh.new()
				sphere.radius = size.x * 0.24
				sphere.height = size.x * 0.48
				var instance := MeshInstance3D.new()
				instance.mesh = sphere
				instance.material_override = mat
				var angle := TAU * float(i) / float(count)
				instance.position = Vector3(cos(angle) * size.x * 0.26, 0.0, sin(angle) * size.z * 0.26)
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(instance)
		"tray":
			root.add_child(_box(Vector3(size.x, size.y, size.z), Vector3.ZERO, mat))
			root.add_child(_box(Vector3(size.x * 0.9, size.y * 0.4, size.z * 0.9),
				Vector3(0, size.y * 0.55, 0), _matte(color.lightened(0.3))))
		_:
			root.add_child(_box(Vector3(size.x, size.y, size.z), Vector3.ZERO, mat))
			# Paper band so boxes read as packaging rather than crates.
			root.add_child(_box(Vector3(size.x * 1.01, size.y * 0.22, size.z * 1.01),
				Vector3(0, 0, 0), _matte(color.lightened(0.45))))

	# A barcode stripe on the front face for items you inspect.
	if shape != "bunch":
		root.add_child(_box(Vector3(size.x * 0.5, 0.012, 0.006),
			Vector3(0, -size.y * 0.34, size.z * 0.51), _matte(Color(0.96, 0.97, 0.96))))
	return root


static func _size_of(product: Dictionary) -> Vector3:
	var size_data: Array = product.get("size", [0.2, 0.2, 0.15])
	if size_data.size() < 3:
		return Vector3(0.2, 0.2, 0.15)
	return Vector3(float(size_data[0]), float(size_data[1]), float(size_data[2]))


static func _color_of(product: Dictionary) -> Color:
	return Color.html(str(product.get("color", "#cccccc")).replace("#", ""))


static func _matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.72
	return material


static func _box(size: Vector3, position: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


static func _cylinder(radius: float, height: float, material: Material, position: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


# --- Real models ------------------------------------------------------------

## Returns a scaled, centred wrapper around res://models/products/<id>.glb, or
## null when there is no model for this product (procedural fallback wins).
static func _try_model(product: Dictionary) -> Node3D:
	var id := str(product.get("id", ""))
	if id.is_empty():
		return null
	var path := MODEL_DIR + id + ".glb"
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var model := packed.instantiate() as Node3D
	if model == null:
		return null

	var root := Node3D.new()
	root.name = "Model_%s" % id
	root.add_child(model)
	_normalise_model(model, _size_of(product))
	# Optional per-product yaw (degrees) if the label faces the wrong way.
	var yaw := float(product.get("model_yaw", 0.0))
	if not is_zero_approx(yaw):
		model.rotation_degrees.y = yaw
	_disable_shadows(root)
	return root


static func _normalise_model(model: Node3D, target: Vector3) -> void:
	var bounds := _bounds(model, Transform3D.IDENTITY)
	if bounds.size == Vector3.ZERO:
		return
	var factor := minf(
		target.x / maxf(bounds.size.x, 0.0001),
		minf(target.y / maxf(bounds.size.y, 0.0001), target.z / maxf(bounds.size.z, 0.0001))
	)
	if factor <= 0.0 or not is_finite(factor):
		return
	model.scale = Vector3.ONE * factor
	# Centre the model on the item origin so it sits on the belt and in the
	# collider the same way the procedural prop does.
	model.position = -bounds.get_center() * factor


static func _bounds(node: Node, accum: Transform3D) -> AABB:
	var result := AABB()
	var found := false
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		result = accum * (node as MeshInstance3D).get_aabb()
		found = true
	for child in node.get_children():
		var child_transform := accum
		if child is Node3D:
			child_transform = accum * (child as Node3D).transform
		var child_bounds := _bounds(child, child_transform)
		if child_bounds.size == Vector3.ZERO:
			continue
		result = child_bounds if not found else result.merge(child_bounds)
		found = true
	return result if found else AABB()


static func _disable_shadows(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_disable_shadows(child)
