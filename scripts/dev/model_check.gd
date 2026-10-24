extends Node
## Loads a product model and prints what the importer produced, so orientation
## and scale can be checked without eyeballing the game.
##
##   godot --headless --path . -- --modelcheck=milk

func _ready() -> void:
	var id := "milk"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--modelcheck="):
			id = arg.get_slice("=", 1)

	if id == "body":
		_check_body()
		get_tree().quit(0)
		return

	if id.begins_with("customer"):
		_check_customer(id)
		get_tree().quit(0)
		return
	var path := "res://models/products/%s.glb" % id
	print("[MODEL] exists=", ResourceLoader.exists(path), " path=", path)
	if ResourceLoader.exists(path):
		var packed := load(path) as PackedScene
		if packed == null:
			print("[MODEL] load failed")
		else:
			var inst := packed.instantiate() as Node3D
			print("[MODEL] root=", inst.name, " children=", inst.get_child_count())
			_dump(inst, 0)
			var bounds := ProductMesh._bounds(inst, Transform3D.IDENTITY)
			print("[MODEL] raw aabb size=", bounds.size, " centre=", bounds.get_center())
			var meshes := 0
			var tris := 0
			for node in inst.find_children("*", "MeshInstance3D", true, false):
				meshes += 1
				var mi := node as MeshInstance3D
				if mi.mesh is ArrayMesh:
					var arrays := (mi.mesh as ArrayMesh).surface_get_arrays(0)
					if arrays.size() > 0:
						tris += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
			print("[MODEL] meshes=", meshes, " tris=", tris)
			var product := GameData.get_product(id)
			var built := ProductMesh.build(product)
			print("[MODEL] built node=", built.name, " wrapper_children=", built.get_child_count())
			if built.get_child_count() > 0:
				var inner := built.get_child(0) as Node3D
				print("[MODEL] normalised scale=", inner.scale, " position=", inner.position)
	get_tree().quit(0)


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	print("[MODEL] %s%s (%s)" % [pad, node.name, node.get_class()])
	for child in node.get_children():
		_dump(child, depth + 1)


##   godot --headless --path . -- --modelcheck=body
## Builds a customer body and reports what the loader resolved: is the rig in
## use, which bones were found, which clips, and where the anchors ended up.
func _check_body() -> void:
	var body := CustomerBody.new()
	add_child(body)
	body.build(99, {})
	print("[BODY] using_model=", body.using_model, " path=", body.model_path)
	print("[BODY] head_bone=", body._head_bone, " neck_bone=", body._neck_bone,
		" hands=", body._hand_l_bone, "/", body._hand_r_bone)
	print("[BODY] walk=", body._walk_clip, " idle=", body._idle_clip)
	print("[BODY] meshes=", body.find_children("*", "MeshInstance3D", true, false).size())
	if body._model_root != null:
		print("[BODY] model scale=", body._model_root.scale, " y=", body._model_root.position.y)
	print("[BODY] head=", body.head.global_position if body.head else "null",
		" hand_l=", body.hand_l.global_position if body.hand_l else "null",
		" hand_r=", body.hand_r.global_position if body.hand_r else "null")
	print("[BODY] anomaly probe: applying extra_finger")
	body.apply_anomaly({"visual": {"kind": "extra_finger"}})
	print("[BODY] extra_fingers=", body._extra_fingers.size(), " out=", body.extra_fingers_out)
	body.free()


##   godot --headless --path . -- --modelcheck=customer_b
## Prints the skeleton, clips and material names a rigged customer produced,
## so the loader and the per-customer tinting can be checked headlessly.
func _check_customer(id: String) -> void:
	var path := "res://models/customers/%s.glb" % id
	print("[CUST] exists=", ResourceLoader.exists(path), " path=", path)
	if not ResourceLoader.exists(path):
		return
	var inst := (load(path) as PackedScene).instantiate() as Node3D
	var skeleton := _first_of(inst, "Skeleton3D") as Skeleton3D
	var anim := _first_of(inst, "AnimationPlayer") as AnimationPlayer
	print("[CUST] root=", inst.name, " children=", inst.get_child_count())
	if skeleton != null:
		var names: Array[String] = []
		for index in skeleton.get_bone_count():
			names.append(skeleton.get_bone_name(index))
		print("[CUST] bones=", skeleton.get_bone_count(), " ", ", ".join(names))
		for needed in ["Head", "Neck", "Hand.R", "Hand.L", "FingerExtra0.R", "FingerExtra1.L"]:
			print("[CUST] bone ", needed, "=", skeleton.find_bone(needed))
	if anim != null:
		for clip in anim.get_animation_list():
			var animation := anim.get_animation(clip)
			print("[CUST] clip ", clip, " len=", snappedf(animation.length, 0.01),
				"s tracks=", animation.get_track_count())
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			var material := mi.mesh.surface_get_material(surface)
			print("[CUST] surface ", surface, " material=",
				material.resource_name if material else "<none>")
	print("[CUST] aabb=", _aabb(inst))
	inst.free()


func _aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	for child in node.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi.mesh == null:
			continue
		var box: AABB = mi.global_transform * mi.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


func _first_of(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _first_of(child, type_name)
		if found != null:
			return found
	return null
