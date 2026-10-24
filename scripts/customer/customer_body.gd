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


func build(seed_value: int, options: Dictionary = {}) -> void:
	rng.seed = seed_value
	height_scale = float(options.get("height_scale", rng.randf_range(0.92, 1.08)))
	body_width = float(options.get("body_width", rng.randf_range(0.9, 1.12)))
	skin = SKIN_TONES[rng.randi_range(0, SKIN_TONES.size() - 1)]
	shirt = SHIRT_COLORS[rng.randi_range(0, SHIRT_COLORS.size() - 1)]
	hair_color = HAIR_COLORS[rng.randi_range(0, HAIR_COLORS.size() - 1)]
	_make_materials()
	_build_body()
	_build_shadow()
	for anomaly in options.get("anomalies", []):
		apply_anomaly(anomaly)


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


func unfreeze() -> void:
	_frozen = false


func is_frozen() -> bool:
	return _frozen


func set_shadow_lag(amount: float) -> void:
	if shadow_blob:
		shadow_blob.position.x = amount * 0.6
		shadow_blob.position.z = amount * 0.9
		shadow_blob.scale = Vector3(1.0 + absf(amount) * 0.5, 1.0, 1.0)


func raise_arm(side: String = "right") -> void:
	var shoulder := shoulder_r if side == "right" else shoulder_l
	var tween := create_tween()
	tween.tween_property(shoulder, "rotation:x", -1.15, 0.35).set_trans(Tween.TRANS_SINE)
	tween.tween_interval(0.45)
	tween.tween_property(shoulder, "rotation:x", 0.0, 0.55).set_trans(Tween.TRANS_SINE)


func apply_anomaly(anomaly: Dictionary) -> void:
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
