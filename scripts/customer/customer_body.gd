class_name CustomerBody
extends Node3D
## Procedurally assembled low-poly person with an animation layer.
##
## One rig is ~20 small meshes, which keeps three or four simultaneous
## shoppers cheap enough for handheld hardware.

const SKIN_TONES := [
	Color(0.96, 0.80, 0.68), Color(0.88, 0.70, 0.55), Color(0.74, 0.55, 0.40),
	Color(0.55, 0.39, 0.28), Color(0.38, 0.26, 0.19), Color(0.24, 0.17, 0.13),
]
const HAIR_COLORS := [
	Color(0.08, 0.06, 0.05), Color(0.18, 0.12, 0.08), Color(0.42, 0.28, 0.15),
	Color(0.62, 0.48, 0.28), Color(0.75, 0.72, 0.66), Color(0.30, 0.30, 0.34),
]
const SHIRT_COLORS := [
	Color(0.24, 0.32, 0.44), Color(0.52, 0.28, 0.28), Color(0.30, 0.42, 0.32),
	Color(0.62, 0.60, 0.52), Color(0.34, 0.30, 0.40), Color(0.68, 0.55, 0.30),
	Color(0.22, 0.24, 0.28), Color(0.56, 0.44, 0.52),
]

var rng := RandomNumberGenerator.new()
var height_scale := 1.0
var body_width := 1.0

var head: Node3D
var neck: Node3D
var torso: Node3D
var shoulder_l: Node3D
var shoulder_r: Node3D
var elbow_l: Node3D
var elbow_r: Node3D
var hand_l: Node3D
var hand_r: Node3D
var hip_l: Node3D
var hip_r: Node3D
var knee_l: Node3D
var knee_r: Node3D
var eyes: Array[MeshInstance3D] = []
var pupil_l: MeshInstance3D
var pupil_r: MeshInstance3D
var mouth: Node3D
var teeth_root: Node3D
var eyebrow_l: MeshInstance3D
var eyebrow_r: MeshInstance3D
var shadow_blob: MeshInstance3D
var silhouette: MeshInstance3D

var skin: Color = Color(0.9, 0.75, 0.62)
var shirt: Color = Color(0.3, 0.35, 0.4)
var hair_color: Color = Color(0.1, 0.08, 0.07)

var blink_mode := "normal"        ## normal | never | fast | frozen
var breathing := true
var mouth_open := 0.0
var smile_width := 1.0
var head_turn_limit := 1.2

var _blink_timer := 2.0
var _blink_progress := -1.0
var _breathe_time := 0.0
var _walk_time := 0.0
var _walk_blend := 0.0
var _frozen := false
var _materials: Dictionary = {}

## Real rigged characters. Any glb listed here is tried in turn; the first one
## that loads replaces the primitive body. Bone tricks cover the anomalies these
## meshes can express (neck angle, long hands, head turns, freeze, glitch); the
## ones that need facial geometry only exist on the primitive fallback.
const MODEL_PATHS := [
	"res://models/customers/customer_man.glb",
]
## Height the model is normalised to before the per-customer height variation.
const MODEL_HEIGHT := 1.78
## This export faces +Z (toes measured at +0.18 in bind space); the game's forward
## is -Z, so the model is turned around to walk the way it is moving.
const MODEL_YAW_DEG := 180.0
var model_path := ""
var using_model := false
var _model_root: Node3D
var _skeleton: Skeleton3D
var _anim: AnimationPlayer
var _head_bone := -1
var _neck_bone := -1
var _hand_r_bone := -1
var _hand_l_bone := -1
var _extra_fingers: Array[int] = []
var extra_fingers_out := false
var _walk_clip := ""
var _idle_clip := ""
## Test hook: force a specific model, bypassing MODEL_PATHS.
var model_override := ""


func build(seed_value: int, options: Dictionary = {}) -> void:
	rng.seed = seed_value
	height_scale = float(options.get("height_scale", rng.randf_range(0.92, 1.08)))
	body_width = float(options.get("body_width", rng.randf_range(0.9, 1.12)))
	skin = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)]
	shirt = SHIRT_COLORS[rng.randi_range(0, SHIRT_COLORS.size() - 1)]
	hair_color = HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)]

	if _try_models():
		_build_shadow()
		for anomaly in options.get("anomalies", []):
			apply_anomaly(anomaly)
		return

	_make_materials()
	_build_body()
	_build_shadow()
	for anomaly in options.get("anomalies", []):
		apply_anomaly(anomaly)


## Try every installed model. load() is used directly instead of gating on
## ResourceLoader.exists(): in an exported build an imported .glb resolves through
## a remap, and exists() is not a reliable answer there.
func _try_models() -> bool:
	var order := MODEL_PATHS.duplicate()
	var override := str(model_override)
	if not override.is_empty():
		order = [override]
	else:
		order.shuffle()
	for path in order:
		model_path = path
		if _build_from_model():
			return true
	model_path = ""
	return false


func _build_from_model() -> bool:
	var packed := load(model_path) as PackedScene
	if packed == null:
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false
	model.name = "Model"
	add_child(model)
	_model_root = model

	_skeleton = _find_of_type(model, "Skeleton3D") as Skeleton3D
	_anim = _find_of_type(model, "AnimationPlayer") as AnimationPlayer
	if _skeleton == null:
		model.queue_free()
		_model_root = null
		return false

	_normalise_model(model)
	_resolve_bones()
	_resolve_clips()

	_strip_extra_finger_tracks()
	_apply_finger_visibility()
	_tint_model()

	head = _anchor_for_bone(_head_bone, Vector3.ZERO, Vector3(0.0, 1.62, 0.0))
	neck = _anchor_for_bone(_neck_bone, Vector3.ZERO, Vector3(0.0, 1.45, 0.0))
	torso = _anchor_for_bone(2, Vector3.ZERO, Vector3(0.0, 1.15, 0.0))
	hand_r = _anchor_for_bone(_hand_r_bone, Vector3.ZERO, Vector3(-0.25, 0.95, 0.0))
	hand_l = _anchor_for_bone(_hand_l_bone, Vector3.ZERO, Vector3(0.25, 0.95, 0.0))
	mouth = _anchor_for_bone(_head_bone, Vector3(0.0, -0.08, -0.10), Vector3(0.0, 1.58, -0.10))
	if _anim != null and not _idle_clip.is_empty():
		_anim.play(_idle_clip)
	using_model = true
	return true


## Attach to a bone when it exists, otherwise park a plain node at a sensible
## offset so the inspection camera still has something to aim at.
func _anchor_for_bone(index: int, offset: Vector3, fallback: Vector3) -> Node3D:
	if _skeleton != null and index >= 0 and index < _skeleton.get_bone_count():
		var anchor := _bone_anchor(_skeleton.get_bone_name(index), offset)
		if anchor.get_parent() is BoneAttachment3D:
			return anchor
		if anchor.get_parent() == self:
			remove_child(anchor)
			anchor.queue_free()
	var node := Node3D.new()
	node.position = fallback
	add_child(node)
	return node


## Scale the model so the skeleton spans MODEL_HEIGHT and stand it on y = 0.
## Bone positions are used rather than the mesh AABB: a skinned mesh reports its
## bind-space bounds, which are not in the same orientation as the posed skeleton.
func _normalise_model(model: Node3D) -> void:
	var bounds := _model_bounds_from_bones()
	if bounds.size.y <= 0.001:
		model.scale = Vector3.ONE
		return
	# Bones stop at the skull joint, so aim slightly under the full body height.
	var fit := (MODEL_HEIGHT * height_scale * 0.94) / bounds.size.y
	model.scale = Vector3(fit * body_width, fit, fit * body_width)
	model.rotation.y = deg_to_rad(MODEL_YAW_DEG)
	model.position.y = (-bounds.position.y + 0.03) * model.scale.y


func _model_bounds_from_bones() -> AABB:
	var out := AABB()
	var first := true
	var to_self := global_transform.affine_inverse() if is_inside_tree() else Transform3D.IDENTITY
	for index in _skeleton.get_bone_count():
		var point: Vector3 = to_self * (_skeleton.global_transform * _skeleton.get_bone_global_rest(index).origin)
		if first:
			out = AABB(point, Vector3.ZERO)
			first = false
		else:
			out = out.expand(point)
	return out


func _bone_depth(index: int) -> int:
	var depth := 0
	var current := _skeleton.get_bone_parent(index)
	while current >= 0 and depth < 32:
		depth += 1
		current = _skeleton.get_bone_parent(current)
	return depth


func _model_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var box: AABB = _offset_from(instance, root) * instance.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## Transform of node relative to root, without needing either of them in a tree.
func _offset_from(node: Node3D, root: Node3D) -> Transform3D:
	var out := Transform3D.IDENTITY
	var current: Node3D = node
	while current != null and current != root:
		out = current.transform * out
		current = current.get_parent() as Node3D
	return out


## Bone names differ wildly between rigs (Hand.R, mixamorig:LeftHand,
## Skeleton_arm_joint_L__4_...). Match on patterns rather than exact names.
func _resolve_bones() -> void:
	_head_bone = -1
	_neck_bone = -1
	_hand_r_bone = -1
	_hand_l_bone = -1
	_extra_fingers.clear()
	var left_depth := -1
	var right_depth := -1
	for index in _skeleton.get_bone_count():
		var bone := str(_skeleton.get_bone_name(index)).to_lower()
		if _neck_bone < 0 and bone.contains("neck"):
			_neck_bone = index
		if bone.contains("head"):
			_head_bone = index
		elif _head_bone < 0 and bone.contains("neck") and bone.contains("2"):
			_head_bone = index
		if bone.contains("fingerextra"):
			_extra_fingers.append(index)
			continue
		# Hands: deepest wrist/hand bone on each side. Digits are skipped so a
		# thumb tip does not become the anchor.
		var is_digit := bone.contains("thumb") or bone.contains("finger") or bone.contains("index") \
			or bone.contains("middle") or bone.contains("ring") or bone.contains("pinky")
		if is_digit:
			continue
		var is_hand := bone.contains("hand") or bone.contains("wrist") or bone.contains("arm_joint")
		if not is_hand:
			continue
		var depth := _bone_depth(index)
		var looks_left := bone.contains("left") or bone.contains("arm_joint_l") or bone.ends_with(".l") \
			or bone.ends_with("_l")
		var looks_right := bone.contains("right") or bone.contains("arm_joint_r") or bone.ends_with(".r") \
			or bone.ends_with("_r")
		if looks_left and depth > left_depth:
			left_depth = depth
			_hand_l_bone = index
		elif looks_right and depth > right_depth:
			right_depth = depth
			_hand_r_bone = index
	if _head_bone < 0:
		_head_bone = _neck_bone
	if _neck_bone < 0:
		_neck_bone = _head_bone


## Clip names vary as much as bone names, and some exports ship a single unnamed
## walk cycle. Fall back to whatever is there rather than standing still.
func _resolve_clips() -> void:
	_walk_clip = ""
	_idle_clip = ""
	if _anim == null:
		return
	var names := _anim.get_animation_list()
	if names.is_empty():
		return
	for name in names:
		var clip := str(name).to_lower()
		if clip.contains("walk") and _walk_clip.is_empty():
			_walk_clip = str(name)
		elif clip.contains("idle") and _idle_clip.is_empty():
			_idle_clip = str(name)
	if _walk_clip.is_empty():
		for name in names:
			if str(name).to_lower().contains("run"):
				_walk_clip = str(name)
				break
	if _walk_clip.is_empty():
		_walk_clip = str(names[0])
	if _idle_clip.is_empty():
		_idle_clip = _walk_clip


func _find_of_type(node: Node, type_name: String) -> Node:
	if node.is_class(type_name):
		return node
	for child in node.get_children():
		var found := _find_of_type(child, type_name)
		if found != null:
			return found
	return null


## The clips key every bone's scale, which would force the hidden extra digits
## back to full size every frame. Drop only those scale tracks so the pose holds.
func _strip_extra_finger_tracks() -> void:
	if _anim == null:
		return
	for anim_name in _anim.get_animation_list():
		var anim := _anim.get_animation(anim_name)
		if anim == null:
			continue
		for i in range(anim.get_track_count() - 1, -1, -1):
			if anim.track_get_type(i) != Animation.TYPE_SCALE_3D:
				continue
			if str(anim.track_get_path(i)).contains("FingerExtra"):
				anim.remove_track(i)


func _apply_finger_visibility() -> void:
	if _skeleton == null:
		return
	var target := Vector3.ONE if extra_fingers_out else Vector3.ZERO
	for index in _extra_fingers:
		_skeleton.set_bone_pose_scale(index, target)


## Recolour the imported materials so two customers are never identical.
func _tint_model() -> void:
	if _model_root == null:
		return
	var pants := shirt.darkened(0.55)
	# For models with one textured material (every part in one skin) a name match
	# never happens, so a muted multiply tint gives each customer its own look.
	var tint := Color(0.82, 0.82, 0.82).lerp(shirt, 0.45).darkened(rng.randf_range(0.0, 0.22))
	for mesh in _model_root.find_children("*", "MeshInstance3D", true, false) as Array[MeshInstance3D]:
		var mesh_resource := mesh.mesh
		if mesh_resource == null:
			continue
		for index in mesh_resource.get_surface_count():
			var source := mesh_resource.surface_get_material(index)
			if source == null:
				continue
			var duplicate := source.duplicate() as StandardMaterial3D
			if duplicate == null:
				continue
			var name_hint := (str(duplicate.resource_name) + " " + str(source.resource_name)).to_lower()
			if name_hint.contains("skin"):
				duplicate.albedo_color = skin
			elif name_hint.contains("shirt"):
				duplicate.albedo_color = shirt
			elif name_hint.contains("pant"):
				duplicate.albedo_color = pants
			elif name_hint.contains("hair") or name_hint.contains("brow"):
				duplicate.albedo_color = hair_color
			else:
				duplicate.albedo_color = tint
			mesh.set_surface_override_material(index, duplicate)


## Marker that follows a bone, used by inspection to aim at body parts.
func _bone_anchor(bone_name: String, offset: Vector3) -> Node3D:
	var anchor := Node3D.new()
	anchor.name = "Anchor_%s" % bone_name.replace(".", "_")
	if _skeleton == null or _skeleton.find_bone(bone_name) < 0:
		add_child(anchor)
		return anchor
	var attachment := BoneAttachment3D.new()
	attachment.bone_name = bone_name
	_skeleton.add_child(attachment)
	anchor.position = offset
	attachment.add_child(anchor)
	return anchor


func _make_materials() -> void:
	_materials["skin"] = _matte(skin)
	_materials["shirt"] = _matte(shirt)
	_materials["pants"] = _matte(shirt.darkened(0.55))
	_materials["hair"] = _matte(hair_color)
	_materials["shoe"] = _matte(Color(0.08, 0.08, 0.09))
	_materials["eye"] = _matte(Color(0.94, 0.94, 0.92))
	_materials["pupil"] = _matte(Color(0.06, 0.06, 0.08))
	_materials["mouth"] = _matte(Color(0.30, 0.10, 0.12))
	_materials["teeth"] = _matte(Color(0.96, 0.95, 0.90))


func _matte(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	return material


func _part(size: Vector3, position: Vector3, material_key: String, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _materials[material_key]
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _sphere(radius: float, position: Vector3, material_key: String, parent: Node3D) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 6
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _materials[material_key]
	instance.position = position
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _build_body() -> void:
	scale = Vector3(body_width, height_scale, body_width)

	torso = Node3D.new()
	torso.name = "Torso"
	torso.position = Vector3(0, 0.98, 0)
	add_child(torso)
	_part(Vector3(0.44, 0.56, 0.26), Vector3.ZERO, "shirt", torso)
	_part(Vector3(0.46, 0.12, 0.28), Vector3(0, -0.30, 0), "pants", torso)

	neck = Node3D.new()
	neck.name = "Neck"
	neck.position = Vector3(0, 0.30, 0)
	torso.add_child(neck)
	_part(Vector3(0.13, 0.10, 0.13), Vector3.ZERO, "skin", neck)

	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.20, 0)
	neck.add_child(head)
	_part(Vector3(0.26, 0.29, 0.25), Vector3.ZERO, "skin", head)
	_part(Vector3(0.27, 0.09, 0.26), Vector3(0, 0.145, 0), "hair", head)
	_part(Vector3(0.27, 0.12, 0.06), Vector3(0, 0.075, -0.115), "hair", head)
	if rng.randf() < 0.35:
		_part(Vector3(0.10, 0.16, 0.08), Vector3(0.13, 0.06, 0.02), "hair", head)
	_part(Vector3(0.05, 0.06, 0.05), Vector3(0, -0.01, -0.14), "skin", head)

	var eye_y := 0.045
	for side in [-1.0, 1.0]:
		var eye := _sphere(0.032, Vector3(side * 0.068, eye_y, -0.128), "eye", head)
		eye.scale = Vector3(1.0, 1.0, 0.55)
		eyes.append(eye)
	var pupil_left := _sphere(0.016, Vector3(-0.068, eye_y, -0.152), "pupil", head)
	pupil_left.scale = Vector3(1.0, 1.0, 0.5)
	pupil_l = pupil_left
	var pupil_right := _sphere(0.016, Vector3(0.068, eye_y, -0.152), "pupil", head)
	pupil_right.scale = Vector3(1.0, 1.0, 0.5)
	pupil_r = pupil_right

	eyebrow_l = _part(Vector3(0.07, 0.014, 0.02), Vector3(-0.068, 0.088, -0.132), "hair", head)
	eyebrow_r = _part(Vector3(0.07, 0.014, 0.02), Vector3(0.068, 0.088, -0.132), "hair", head)

	mouth = Node3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(0, -0.085, -0.128)
	head.add_child(mouth)
	_part(Vector3(0.10, 0.022, 0.02), Vector3.ZERO, "mouth", mouth)
	teeth_root = Node3D.new()
	teeth_root.name = "Teeth"
	teeth_root.position = Vector3(0, 0.012, -0.004)
	mouth.add_child(teeth_root)
	for i in 6:
		_part(Vector3(0.013, 0.011, 0.01), Vector3(-0.032 + i * 0.013, 0, 0), "teeth", teeth_root)
	teeth_root.visible = false

	# Arms
	shoulder_l = Node3D.new()
	shoulder_l.position = Vector3(-0.27, 0.22, 0)
	torso.add_child(shoulder_l)
	_part(Vector3(0.11, 0.30, 0.13), Vector3(0, -0.15, 0), "shirt", shoulder_l)
	elbow_l = Node3D.new()
	elbow_l.position = Vector3(0, -0.30, 0)
	shoulder_l.add_child(elbow_l)
	_part(Vector3(0.10, 0.28, 0.11), Vector3(0, -0.14, 0), "skin", elbow_l)
	hand_l = Node3D.new()
	hand_l.position = Vector3(0, -0.30, 0)
	elbow_l.add_child(hand_l)
	_build_hand(hand_l, -1.0)

	shoulder_r = Node3D.new()
	shoulder_r.position = Vector3(0.27, 0.22, 0)
	torso.add_child(shoulder_r)
	_part(Vector3(0.11, 0.30, 0.13), Vector3(0, -0.15, 0), "shirt", shoulder_r)
	elbow_r = Node3D.new()
	elbow_r.position = Vector3(0, -0.30, 0)
	shoulder_r.add_child(elbow_r)
	_part(Vector3(0.10, 0.28, 0.11), Vector3(0, -0.14, 0), "skin", elbow_r)
	hand_r = Node3D.new()
	hand_r.position = Vector3(0, -0.30, 0)
	elbow_r.add_child(hand_r)
	_build_hand(hand_r, 1.0)

	# Legs
	hip_l = Node3D.new()
	hip_l.position = Vector3(-0.11, 0.62, 0)
	add_child(hip_l)
	_part(Vector3(0.15, 0.42, 0.16), Vector3(0, -0.20, 0), "pants", hip_l)
	knee_l = Node3D.new()
	knee_l.position = Vector3(0, -0.42, 0)
	hip_l.add_child(knee_l)
	_part(Vector3(0.13, 0.40, 0.14), Vector3(0, -0.20, 0), "pants", knee_l)
	_part(Vector3(0.14, 0.08, 0.24), Vector3(0, -0.42, -0.05), "shoe", knee_l)

	hip_r = Node3D.new()
	hip_r.position = Vector3(0.11, 0.62, 0)
	add_child(hip_r)
	_part(Vector3(0.15, 0.42, 0.16), Vector3(0, -0.20, 0), "pants", hip_r)
	knee_r = Node3D.new()
	knee_r.position = Vector3(0, -0.42, 0)
	hip_r.add_child(knee_r)
	_part(Vector3(0.13, 0.40, 0.14), Vector3(0, -0.20, 0), "pants", knee_r)
	_part(Vector3(0.14, 0.08, 0.24), Vector3(0, -0.42, -0.05), "shoe", knee_r)


func _build_hand(hand: Node3D, side: float) -> void:
	_part(Vector3(0.075, 0.10, 0.045), Vector3(0, -0.04, 0), "skin", hand)
	for i in 4:
		_part(Vector3(0.016, 0.055, 0.02), Vector3(-0.026 + i * 0.018, -0.115, 0), "skin", hand)
	_part(Vector3(0.02, 0.04, 0.03), Vector3(0.045 * side, -0.06, 0.01), "skin", hand)


func _build_shadow() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.85)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0, 0, 0, 0.34)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var instance := MeshInstance3D.new()
	instance.mesh = quad
	instance.material_override = material
	instance.rotation.x = -PI * 0.5
	instance.position = Vector3(0, 0.02, 0)
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	shadow_blob = instance


func set_silhouette() -> void:
	if silhouette != null:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.58, 2.65, 0.52)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.02, 0.02, 0.025)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = Vector3(0, 1.3, 0)
	instance.layers = 4  # visual layer 3: seen by the security camera only
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	silhouette = instance


func set_skin_glitch(enabled: bool) -> void:
	if using_model:
		for mesh in _model_root.find_children("*", "MeshInstance3D", true, false) as Array[MeshInstance3D]:
			if enabled:
				var dark := StandardMaterial3D.new()
				dark.albedo_color = Color(0.05, 0.05, 0.06)
				dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				mesh.material_override = dark
			else:
				mesh.material_override = null
		return
	var skin_mat: StandardMaterial3D = _materials["skin"]
	var shirt_mat: StandardMaterial3D = _materials["shirt"]
	if enabled:
		skin_mat.albedo_color = Color(0.12, 0.11, 0.10)
		shirt_mat.albedo_color = Color(0.05, 0.05, 0.06)
	else:
		skin_mat.albedo_color = skin
		shirt_mat.albedo_color = shirt


# --- Animation --------------------------------------------------------------

func animate(delta: float, speed: float, looking_at: Vector3 = Vector3.ZERO) -> void:
	if using_model:
		_animate_model(delta, speed, looking_at)
		return
	if _frozen:
		return
	_walk_blend = lerpf(_walk_blend, clampf(speed / 1.6, 0.0, 1.0), delta * 5.0)
	_walk_time += delta * (2.0 + speed * 2.4)

	var swing := sin(_walk_time) * 0.62 * _walk_blend
	hip_l.rotation.x = swing
	hip_r.rotation.x = -swing
	knee_l.rotation.x = maxf(0.0, -swing) * 1.1
	knee_r.rotation.x = maxf(0.0, swing) * 1.1
	shoulder_l.rotation.x = -swing * 0.55
	shoulder_r.rotation.x = swing * 0.55
	elbow_l.rotation.x = -0.12 - absf(swing) * 0.2
	elbow_r.rotation.x = -0.12 - absf(swing) * 0.2

	if breathing and blink_mode != "frozen":
		_breathe_time += delta
		var breath := sin(_breathe_time * 1.5) * 0.006
		torso.scale = Vector3(1.0, 1.0 + breath, 1.0)
		torso.position.y = 0.98 + absf(sin(_walk_time)) * 0.012 * _walk_blend

	_animate_blink(delta)
	_animate_mouth(delta)

	if looking_at != Vector3.ZERO:
		_face_head_towards(looking_at, delta)


func _animate_blink(delta: float) -> void:
	if blink_mode == "never" or blink_mode == "frozen":
		return
	var rate := 9.0 if blink_mode == "fast" else 7.0
	if _blink_progress < 0.0:
		_blink_timer -= delta
		if _blink_timer <= 0.0:
			_blink_progress = 0.0
			_blink_timer = 0.24 if blink_mode == "fast" else rng.randf_range(2.4, 5.4)
		return
	_blink_progress += delta * rate
	if _blink_progress >= 1.0:
		_blink_progress = -1.0
		_set_eye_openness(1.0)
	else:
		_set_eye_openness(absf(cos(_blink_progress * PI)))


func _set_eye_openness(value: float) -> void:
	var amount := maxf(0.08, value)
	for eye in eyes:
		eye.scale.y = amount
	if pupil_l:
		pupil_l.scale.y = amount
	if pupil_r:
		pupil_r.scale.y = amount


func _animate_mouth(delta: float) -> void:
	if mouth_open > 0.0:
		mouth_open = maxf(0.0, mouth_open - delta * 2.5)
	var target := 1.0 + mouth_open * 2.2
	mouth.scale.y = lerpf(mouth.scale.y, target, delta * 12.0)


func speak() -> void:
	if using_model:
		return
	mouth_open = 1.0
	teeth_root.visible = true


func _face_head_towards(point: Vector3, delta: float) -> void:
	var reference := head.get_parent() as Node3D
	if reference == null:
		return
	var local := reference.to_local(point)
	var yaw := atan2(-local.x, -local.z)
	head.rotation.y = lerp_angle(head.rotation.y, clampf(yaw, -head_turn_limit, head_turn_limit), delta * 3.5)
	var flat := Vector2(local.x, local.z).length()
	var pitch := atan2(local.y - 1.5, maxf(flat, 0.001))
	head.rotation.x = lerpf(head.rotation.x, clampf(-pitch, -0.5, 0.4), delta * 3.0)


func turn_head_to(point: Vector3, snap: bool = false) -> void:
	if using_model:
		_model_head_to(point)
		return
	var reference := head.get_parent() as Node3D
	if reference == null:
		return
	var local := reference.to_local(point)
	var yaw := atan2(-local.x, -local.z)
	head.rotation.y = clampf(yaw, -head_turn_limit, head_turn_limit)
	if snap:
		head.rotation.z = deg_to_rad(rng.randf_range(-9.0, 9.0))


func freeze() -> void:
	_frozen = true
	if using_model and _anim != null:
		_anim.speed_scale = 0.0


func unfreeze() -> void:
	_frozen = false
	if using_model and _anim != null:
		_anim.speed_scale = 1.0


func is_frozen() -> bool:
	return _frozen


func set_shadow_lag(amount: float) -> void:
	if shadow_blob:
		shadow_blob.position.x = amount * 0.6
		shadow_blob.position.z = amount * 0.9
		shadow_blob.scale = Vector3(1.0 + absf(amount) * 0.5, 1.0, 1.0)


func raise_arm(side: String = "right") -> void:
	if using_model:
		return
	var shoulder := shoulder_r if side == "right" else shoulder_l
	var tween := create_tween()
	tween.tween_property(shoulder, "rotation:x", -1.15, 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(0.45)
	tween.tween_property(shoulder, "rotation:x", 0.0, 0.55).set_trans(Tween.TRANS_SINE)


func apply_anomaly(anomaly: Dictionary) -> void:
	if using_model:
		_apply_bone_anomaly(anomaly)
		return
	var visual: Dictionary = anomaly.get("visual", {})
	match str(visual.get("kind", "")):
		"extra_finger":
			_add_fingers(hand_r, 2)
		"eye_offset":
			eyes[0].position.y += 0.014
			pupil_l.position.y += 0.014
			eyebrow_l.position.y += 0.010
		"no_blink":
			blink_mode = "never"
		"fast_blink":
			blink_mode = "fast"
		"wide_smile":
			smile_width = 2.3
			mouth.scale.x = smile_width
		"neck_angle":
			neck.rotation.x = deg_to_rad(-15.0)
			neck.position.x = 0.03
		"long_hands":
			hand_l.scale = Vector3(1.25, 1.7, 1.05)
			hand_r.scale = Vector3(1.25, 1.7, 1.05)
		"uniform_teeth":
			_add_teeth(6)
			teeth_root.visible = true
		"frozen_face":
			blink_mode = "frozen"
		"no_breath":
			breathing = false
		"face_swap":
			set_meta("can_glitch", true)
		"eye_track":
			set_meta("eye_track", true)
		"camera_shape":
			set_silhouette()
		_:
			pass


func _add_fingers(hand: Node3D, count: int) -> void:
	for i in count:
		_part(Vector3(0.016, 0.06, 0.02), Vector3(0.028 + i * 0.017, -0.117, 0), "skin", hand)


func _add_teeth(count: int) -> void:
	for i in count:
		_part(Vector3(0.012, 0.010, 0.009), Vector3(-0.032 + i * 0.0125, 0, 0), "teeth", teeth_root)


## Which world point the head is aimed at, used by the inspection camera.
func head_anchor() -> Node3D:
	return head


func hand_anchor() -> Node3D:
	return hand_r


func eyes_anchor() -> Node3D:
	return pupil_l if pupil_l else head


# --- Rigged-model driving ---------------------------------------------------

func _animate_model(delta: float, speed: float, looking_at: Vector3) -> void:
	if _anim == null or _walk_clip.is_empty():
		return
	var moving := speed > 0.35
	var want := _walk_clip if moving else _idle_clip
	if _anim.current_animation != want:
		_anim.play(want, 0.2)
	if moving:
		_anim.speed_scale = clampf(speed / 1.25, 0.6, 1.8)
	elif want == _walk_clip:
		# Only one clip shipped: crawl it so standing still still breathes.
		_anim.speed_scale = 0.12
	else:
		_anim.speed_scale = 1.0
	if not _extra_fingers.is_empty():
		_apply_finger_visibility()
	if looking_at != Vector3.ZERO:
		_model_head_to(looking_at)


## Aim the head bone at a point. Small clamps keep it inside a human range.
func _model_head_to(point: Vector3) -> void:
	if _skeleton == null or _head_bone < 0:
		return
	var local := global_transform.affine_inverse() * point
	var flat := Vector2(local.x, local.z).length()
	# The model root is turned around, so the head bone's own frame is too.
	var yaw := atan2(-local.x, -local.z) - deg_to_rad(MODEL_YAW_DEG)
	var pitch := atan2(local.y - 1.6, maxf(flat, 0.001))
	var flip := -1.0 if MODEL_YAW_DEG > 90.0 else 1.0
	var yaw_q := Quaternion(Vector3.UP, clampf(yaw, -0.85, 0.85))
	var pitch_q := Quaternion(Vector3.RIGHT, flip * clampf(-pitch, -0.30, 0.30))
	_skeleton.set_bone_pose_rotation(_head_bone, yaw_q * pitch_q)


func _apply_bone_anomaly(anomaly: Dictionary) -> void:
	var visual: Dictionary = anomaly.get("visual", {})
	match str(visual.get("kind", "")):
		"neck_angle":
			if _skeleton != null and _neck_bone >= 0:
				_skeleton.set_bone_pose_rotation(_neck_bone, Quaternion(Vector3.RIGHT, deg_to_rad(-16.0)))
		"long_hands":
			if _skeleton != null:
				if _hand_r_bone >= 0:
					_skeleton.set_bone_pose_scale(_hand_r_bone, Vector3(1.2, 1.55, 1.15))
				if _hand_l_bone >= 0:
					_skeleton.set_bone_pose_scale(_hand_l_bone, Vector3(1.2, 1.55, 1.15))
		"extra_finger":
			extra_fingers_out = true
			_apply_finger_visibility()
		"camera_shape":
			set_silhouette()
		"face_swap":
			set_meta("can_glitch", true)
		"eye_track":
			set_meta("eye_track", true)
		_:
			pass