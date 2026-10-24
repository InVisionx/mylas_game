extends Node
## Unified input: gamepad, keyboard/mouse and touch all drive the same actions.
##
## Actions are registered at runtime (not baked into project.godot) so that
## rebinding on the handheld works for every device and survives restarts.

signal binding_changed(action: String)
signal input_device_changed(device: String)

## action -> { keys: [Key], buttons: [JoyButton], axes: [[axis, dir]] }
const DEFAULTS := {
	"move_forward": { "keys": [KEY_W], "axes": [[JOY_AXIS_LEFT_Y, -1.0]] },
	"move_back": { "keys": [KEY_S], "axes": [[JOY_AXIS_LEFT_Y, 1.0]] },
	"move_left": { "keys": [KEY_A], "axes": [[JOY_AXIS_LEFT_X, -1.0]] },
	"move_right": { "keys": [KEY_D], "axes": [[JOY_AXIS_LEFT_X, 1.0]] },

	"look_left": { "keys": [KEY_LEFT], "axes": [[JOY_AXIS_RIGHT_X, -1.0]] },
	"look_right": { "keys": [KEY_RIGHT], "axes": [[JOY_AXIS_RIGHT_X, 1.0]] },
	"look_up": { "keys": [KEY_UP], "axes": [[JOY_AXIS_RIGHT_Y, -1.0]] },
	"look_down": { "keys": [KEY_DOWN], "axes": [[JOY_AXIS_RIGHT_Y, 1.0]] },

	"interact": { "keys": [KEY_E], "buttons": [JOY_BUTTON_A], "mouse": [MOUSE_BUTTON_LEFT] },
	"cancel": { "keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_B] },
	"inspect": { "keys": [KEY_F], "buttons": [JOY_BUTTON_X] },
	"notebook": { "keys": [KEY_TAB], "buttons": [JOY_BUTTON_Y] },
	"approve": { "keys": [KEY_ENTER], "axes": [[JOY_AXIS_TRIGGER_RIGHT, 1.0]] },
	"reject": { "keys": [KEY_BACKSPACE], "axes": [[JOY_AXIS_TRIGGER_LEFT, 1.0]] },
	"sprint": { "keys": [KEY_SHIFT], "buttons": [JOY_BUTTON_LEFT_STICK] },
	"crouch": { "keys": [KEY_CTRL], "buttons": [JOY_BUTTON_RIGHT_STICK] },
	"zoom": { "keys": [KEY_Q], "buttons": [JOY_BUTTON_LEFT_SHOULDER], "mouse": [MOUSE_BUTTON_RIGHT] },
	"pause": { "keys": [KEY_ESCAPE], "buttons": [JOY_BUTTON_START] },

	"focus_next": { "keys": [KEY_PERIOD], "buttons": [JOY_BUTTON_DPAD_RIGHT] },
	"focus_prev": { "keys": [KEY_COMMA], "buttons": [JOY_BUTTON_DPAD_LEFT] },
	"focus_up": { "keys": [KEY_PAGEUP], "buttons": [JOY_BUTTON_DPAD_UP] },
	"focus_down": { "keys": [KEY_PAGEDOWN], "buttons": [JOY_BUTTON_DPAD_DOWN] },
	"camera_next": { "keys": [KEY_C] },
}

## Virtual analog values fed by the on-screen touch controls.
var virtual_move := Vector2.ZERO
var virtual_look := Vector2.ZERO
var touch_active := false

var _rebind_action := ""
var _rebind_callback := Callable()
var last_device := "keyboard"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_register_all()
	_detect_device()
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _register_all() -> void:
	for action in DEFAULTS.keys():
		var data: Dictionary = DEFAULTS[action]
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		InputMap.action_erase_events(action)
		if SettingsManager.bindings.has(action):
			var overridden := _event_from_binding(SettingsManager.bindings[action])
			if overridden != null:
				InputMap.action_add_event(action, overridden)
				continue
		for key in data.get("keys", []):
			InputMap.action_add_event(action, _key_event(key))
		for button in data.get("buttons", []):
			InputMap.action_add_event(action, _button_event(button))
		for axis_data in data.get("axes", []):
			InputMap.action_add_event(action, _axis_event(axis_data[0], axis_data[1]))
		for mouse_button in data.get("mouse", []):
			InputMap.action_add_event(action, _mouse_event(mouse_button))


func _key_event(keycode: int) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	return event


func _button_event(button: int) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	return event


func _axis_event(axis: int, direction: float) -> InputEventJoypadMotion:
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = direction
	return event


func _mouse_event(button: int) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	return event


# --- Rebinding --------------------------------------------------------------

func start_rebind(action: String, callback: Callable = Callable()) -> void:
	_rebind_action = action
	_rebind_callback = callback


func is_rebinding() -> bool:
	return _rebind_action != ""


func cancel_rebind() -> void:
	_rebind_action = ""
	_rebind_callback = Callable()


func _input(event: InputEvent) -> void:
	_input_device_hint(event)
	if _rebind_action == "":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			cancel_rebind()
			get_viewport().set_input_as_handled()
			return
		_apply_binding(_rebind_action, { "type": "key", "code": event.physical_keycode })
	elif event is InputEventJoypadButton and event.pressed:
		_apply_binding(_rebind_action, { "type": "joy_button", "code": event.button_index })
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.6:
		_apply_binding(_rebind_action, { "type": "joy_axis", "axis": event.axis, "value": signf(event.axis_value) })


func _apply_binding(action: String, binding: Dictionary) -> void:
	SettingsManager.bindings[action] = binding
	SettingsManager.save_settings()
	InputMap.action_erase_events(action)
	var event := _event_from_binding(binding)
	if event != null:
		InputMap.action_add_event(action, event)
	binding_changed.emit(action)
	cancel_rebind()
	if _rebind_callback.is_valid():
		_rebind_callback.call(action)


func _event_from_binding(binding: Dictionary) -> InputEvent:
	match str(binding.get("type", "")):
		"key":
			return _key_event(int(binding.get("code", KEY_E)))
		"joy_button":
			return _button_event(int(binding.get("code", JOY_BUTTON_A)))
		"joy_axis":
			return _axis_event(int(binding.get("axis", JOY_AXIS_TRIGGER_RIGHT)), float(binding.get("value", 1.0)))
		"mouse":
			return _mouse_event(int(binding.get("code", MOUSE_BUTTON_LEFT)))
	return null


func reset_bindings() -> void:
	SettingsManager.bindings.clear()
	SettingsManager.save_settings()
	_register_all()
	for action in DEFAULTS.keys():
		binding_changed.emit(action)


func binding_label(action: String) -> String:
	if SettingsManager.bindings.has(action):
		var b: Dictionary = SettingsManager.bindings[action]
		match str(b.get("type", "")):
			"key":
				return OS.get_keycode_string(int(b.get("code", 0)))
			"joy_button":
				return _joy_button_name(int(b.get("code", 0)))
			"joy_axis":
				var axis := int(b.get("axis", 0))
				if axis == JOY_AXIS_TRIGGER_LEFT:
					return "LT"
				if axis == JOY_AXIS_TRIGGER_RIGHT:
					return "RT"
				return "Axis %d" % axis
	var data: Dictionary = DEFAULTS.get(action, {})
	var keys: Array = data.get("keys", [])
	if not keys.is_empty():
		return OS.get_keycode_string(keys[0])
	var buttons: Array = data.get("buttons", [])
	if not buttons.is_empty():
		return _joy_button_name(buttons[0])
	return "Unbound"


func _joy_button_name(button: int) -> String:
	match button:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_LEFT_STICK: return "LS"
		JOY_BUTTON_RIGHT_STICK: return "RS"
		JOY_BUTTON_START: return "Menu"
		JOY_BUTTON_BACK: return "View"
		JOY_BUTTON_DPAD_UP: return "D-Pad Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Pad Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Pad Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Pad Right"
	return "Btn %d" % button


# --- Device awareness -------------------------------------------------------

func _detect_device() -> void:
	if Input.get_connected_joypads().size() > 0:
		last_device = "gamepad"


func _on_joy_connection_changed(_device: int, connected: bool) -> void:
	last_device = "gamepad" if connected else "keyboard"
	input_device_changed.emit(last_device)


func _input_device_hint(event: InputEvent) -> void:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		if last_device != "gamepad":
			last_device = "gamepad"
			input_device_changed.emit(last_device)
	elif event is InputEventKey or event is InputEventMouseButton:
		if last_device != "keyboard":
			last_device = "keyboard"
			input_device_changed.emit(last_device)


func has_gamepad() -> bool:
	return Input.get_connected_joypads().size() > 0


# --- Value helpers ----------------------------------------------------------

func move_vector() -> Vector2:
	var value := Input.get_vector("move_left", "move_right", "move_forward", "move_back", float(SettingsManager.controls["deadzone"]))
	if touch_active:
		value += virtual_move
	if value.length() > 1.0:
		value = value.normalized()
	return value


func look_vector() -> Vector2:
	var value := Input.get_vector("look_left", "look_right", "look_up", "look_down", float(SettingsManager.controls["deadzone"]))
	if touch_active:
		value += virtual_look
	if value.length() > 1.0:
		value = value.normalized()
	return value


func is_held(action: String) -> bool:
	return Input.is_action_pressed(action)


func just_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)


func is_just_pressed(action: String) -> bool:
	return Input.is_action_just_pressed(action)


func just_released(action: String) -> bool:
	return Input.is_action_just_released(action)


func trigger_strength(action: String) -> float:
	return Input.get_action_strength(action)


func vibrate(weak: float, strong: float, duration: float) -> void:
	if not SettingsManager.controls["vibration"]:
		return
	for device in Input.get_connected_joypads():
		Input.start_joy_vibration(device, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)
