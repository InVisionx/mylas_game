class_name PlayerController
extends CharacterBody3D
## First-person controller. Gamepad, keyboard/mouse and touch all arrive here
## through InputManager's actions.

signal target_changed(target: Node, prompt: String)

const WALK_SPEED := 3.15
const SPRINT_SPEED := 5.1
const CROUCH_SPEED := 1.55
const ACCELERATION := 14.0
const AIR_ACCELERATION := 3.0
const MOUSE_SENSITIVITY_BASE := 0.0022
const STICK_SPEED := 3.1

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera
@onready var ray: RayCast3D = $Head/Camera/InteractRay
@onready var collision: CollisionShape3D = $Collision

var can_look := true
var can_move := true
var input_locked := false

## Focus is a lease too: inspection and jumpscares refresh it every frame, so a
## broken sequence can only freeze the player for a fraction of a second.
var _focus_until_ms := 0

var _pitch := 0.0
var _bob_time := 0.0
var _step_accum := 0.0
var _crouching := false
var _head_height := 1.62
var _shake_amount := 0.0
var _shake_time := 0.0
var _shake_duration := 0.0
var _fov_base := 75.0
var _forced_look := Vector3.ZERO
var _force_until := 0.0
var _target: Node = null
var _prompt := ""

var footsteps_enabled := true


func _ready() -> void:
	add_to_group("player")
	_fov_base = float(SettingsManager.graphics.get("fov", 75.0))
	camera.fov = _fov_base
	if DisplayServer.get_name() != "headless" and not _is_touch_device():
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_pitch = -head.rotation.x


func _is_touch_device() -> bool:
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")


func _unhandled_input(event: InputEvent) -> void:
	if _focus_locked() or input_locked or GameManager.is_paused() or GameManager.is_modal_open():
		return
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var sens: float = float(SettingsManager.controls["sensitivity"])
		var sens_y: float = float(SettingsManager.controls["sensitivity_y"]) * sens
		var invert_x: float = -1.0 if SettingsManager.controls["invert_x"] else 1.0
		var invert_y: float = -1.0 if SettingsManager.controls["invert_y"] else 1.0
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY_BASE * sens * invert_x)
		_pitch = clampf(_pitch - event.relative.y * MOUSE_SENSITIVITY_BASE * sens_y * invert_y, -1.45, 1.45)
		head.rotation.x = _pitch


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= float(ProjectSettings.get_setting("physics/3d/default_gravity", 18.0)) * delta
	else:
		velocity.y = -0.1

	_update_look(delta)

	var move_input := Vector2.ZERO
	if can_move and not _focus_locked() and not input_locked and not GameManager.is_paused() and not GameManager.is_modal_open():
		move_input = InputManager.move_vector()

	var direction := Vector3(move_input.x, 0.0, move_input.y)
	direction = direction.rotated(Vector3.UP, rotation.y)

	var sprinting := InputManager.is_held("sprint") and not _crouching and direction.length() > 0.1
	var speed := WALK_SPEED
	if _crouching:
		speed = CROUCH_SPEED
	elif sprinting:
		speed = SPRINT_SPEED

	var target_velocity := direction * speed
	var accel := ACCELERATION if is_on_floor() else AIR_ACCELERATION
	velocity.x = move_toward(velocity.x, target_velocity.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_velocity.z, accel * delta)

	_handle_crouch(delta)
	move_and_slide()

	_update_head_bob(delta, Vector2(velocity.x, velocity.z).length(), sprinting)
	_update_camera_effects(delta)
	_update_target()


func _update_look(delta: float) -> void:
	if not can_look or _focus_locked() or input_locked or GameManager.is_paused() or GameManager.is_modal_open():
		return
	var look := InputManager.look_vector()
	if look.length() > 0.02:
		var sens: float = float(SettingsManager.controls["sensitivity"])
		var sens_y: float = float(SettingsManager.controls["sensitivity_y"]) * sens
		var invert_x := -1.0 if SettingsManager.controls["invert_x"] else 1.0
		var invert_y := -1.0 if SettingsManager.controls["invert_y"] else 1.0
		rotate_y(-look.x * STICK_SPEED * delta * sens * invert_x)
		_pitch = clampf(_pitch - look.y * STICK_SPEED * 0.7 * delta * sens_y * invert_y, -1.45, 1.45)
		head.rotation.x = _pitch


func _handle_crouch(delta: float) -> void:
	var wants_crouch := false
	if not input_locked and not GameManager.is_paused() and not GameManager.is_modal_open():
		wants_crouch = InputManager.is_held("crouch")
	_crouching = wants_crouch
	var target_height := 1.12 if _crouching else 1.62
	_head_height = move_toward(_head_height, target_height, delta * 3.2)
	head.position.y = _head_height
	var capsule := collision.shape as CapsuleShape3D
	if capsule:
		var target_cap := 1.15 if _crouching else 1.78
		capsule.height = move_toward(capsule.height, target_cap, delta * 4.0)
		collision.position.y = capsule.height * 0.5


func _update_head_bob(delta: float, speed: float, sprinting: bool) -> void:
	var bob_strength := 0.0
	if speed > 0.35 and is_on_floor():
		_bob_time += delta * (9.5 if sprinting else 7.2)
		bob_strength = 0.022 if sprinting else 0.014
		_step_accum += delta * speed
		if _step_accum > 2.05:
			_step_accum = 0.0
			if footsteps_enabled:
				AudioManager.play("step_%d" % randi_range(1, 4), -20.0 if _crouching else -14.0, randf_range(0.94, 1.06))
	camera.position.x = lerpf(camera.position.x, sin(_bob_time * 0.5) * bob_strength, 12.0 * delta)
	camera.position.y = lerpf(camera.position.y, absf(sin(_bob_time)) * bob_strength * 1.4 - 0.008, 12.0 * delta)
	camera.rotation.z = lerpf(camera.rotation.z, sin(_bob_time * 0.5) * bob_strength * 0.6, 8.0 * delta)


func _update_camera_effects(delta: float) -> void:
	if _forced_look != Vector3.ZERO and Time.get_ticks_msec() / 1000.0 < _force_until:
		rotation.y = lerp_angle(rotation.y, _forced_look.y, 8.0 * delta)
		_pitch = lerpf(_pitch, _forced_look.x, 8.0 * delta)
		head.rotation.x = _pitch

	if _shake_time > 0.0:
		_shake_time = maxf(0.0, _shake_time - delta)
		var falloff := _shake_time / maxf(_shake_duration, 0.001)
		var amount := _shake_amount * falloff
		camera.h_offset = randf_range(-amount, amount)
		camera.v_offset = randf_range(-amount, amount)
		if _shake_time <= 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0

	var target_fov := _base_fov()
	camera.fov = lerpf(camera.fov, target_fov, 6.0 * delta)


func _base_fov() -> float:
	return _fov_base + (2.0 if InputManager.is_held("sprint") else 0.0)


func _update_target() -> void:
	ray.force_raycast_update()
	var found: Node = null
	var prompt := ""
	if ray.is_colliding():
		var node := ray.get_collider() as Node
		while node != null:
			if node.has_method("interact"):
				found = node
				break
			node = node.get_parent()
		if found != null:
			if found.has_method("get_interact_prompt"):
				prompt = str(found.call("get_interact_prompt"))
			else:
				prompt = "Interact"
	if found != _target:
		_target = found
		_prompt = prompt
		target_changed.emit(_target, _prompt)
	elif found != null:
		_prompt = prompt


func current_target() -> Node:
	return _target


func current_prompt() -> String:
	return _prompt


func try_interact() -> void:
	if _target == null or not _target.has_method("interact"):
		return
	_target.call("interact", self)


func shake(amount: float, duration: float) -> void:
	_shake_amount = amount * maxf(SettingsManager.horror_intensity(), 0.15)
	_shake_duration = duration
	_shake_time = duration


func force_look_at(point: Vector3, duration: float = 0.0) -> void:
	var eye_height := global_position.y + _head_height
	var direction := Vector3(point.x - global_position.x, 0.0, point.z - global_position.z)
	var yaw := 0.0
	if direction.length() > 0.01:
		var flat := direction.normalized()
		yaw = atan2(-flat.x, -flat.z)
	var distance := direction.length()
	var pitch := 0.0
	if distance > 0.01:
		pitch = atan2(point.y - eye_height, distance)
	_forced_look = Vector3(pitch, yaw, 0.0)
	_force_until = Time.get_ticks_msec() / 1000.0 + duration


func release_forced_look() -> void:
	_forced_look = Vector3.ZERO
	_force_until = 0.0


func set_fov(value: float) -> void:
	_fov_base = value


func focus_mode(enabled: bool, seconds: float = 1.0) -> void:
	if enabled:
		_focus_until_ms = maxi(_focus_until_ms, Time.get_ticks_msec() + int(maxf(seconds, 0.05) * 1000.0))
	else:
		_focus_until_ms = 0
		release_forced_look()


func _focus_locked() -> bool:
	return Time.get_ticks_msec() < _focus_until_ms


## Kept for callers that want to know if the player is currently controllable.
func is_controllable() -> bool:
	return not _focus_locked() and not input_locked and not GameManager.is_paused() and not GameManager.is_modal_open()


func teleport(position: Vector3, look_at_point: Vector3 = Vector3.ZERO) -> void:
	global_position = position
	if look_at_point != Vector3.ZERO:
		force_look_at(look_at_point, 1.5)
