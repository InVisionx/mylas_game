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
