extends CanvasLayer
## On-screen gamepad for touch-only handhelds. Feeds the exact same actions as
## a real controller, so gameplay code never knows the difference.

const MOVE_CENTER := Vector2(250, 830)
const LOOK_CENTER := Vector2(1640, 830)
const STICK_RADIUS := 130.0
const BUTTON_SIZE := 104

var _move_touch := -1
var _look_touch := -1
var _move_origin := Vector2.ZERO
var _look_origin := Vector2.ZERO
var _knob: Panel
var _knob_base: Panel
var _look_active := false


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	InputManager.touch_active = true
	InputManager.virtual_move = Vector2.ZERO
	InputManager.virtual_look = Vector2.ZERO
	_build()


func _build() -> void:
	var pad := Control.new()
	UIKit.full_rect(pad)
	pad.mouse_filter = Control.MOUSE_FILTER_STOP
	pad.gui_input.connect(_on_pad_input)
	add_child(pad)

	_knob_base = _circle(MOVE_CENTER, STICK_RADIUS, Color(1, 1, 1, 0.08), pad)
	_knob = _circle(MOVE_CENTER, 52.0, Color(0.70, 0.95, 0.90, 0.28), pad)
	_circle(LOOK_CENTER, STICK_RADIUS * 0.9, Color(1, 1, 1, 0.05), pad)

	_action_button("interact", "A", Vector2(1710, 900), Color(0.55, 0.9, 0.78))
	_action_button("cancel", "B", Vector2(1580, 985), Color(0.9, 0.6, 0.6))
	_action_button("inspect", "X", Vector2(1580, 815), Color(0.7, 0.8, 1.0))
	_action_button("notebook", "Y", Vector2(1450, 900), Color(0.9, 0.85, 0.6))
	_action_button("approve", "RT", Vector2(1780, 700), Color(0.5, 0.95, 0.6), 132)
	_action_button("reject", "LT", Vector2(1630, 700), Color(0.95, 0.5, 0.5), 132)
	_action_button("zoom", "LB", Vector2(1420, 700), Color(0.7, 0.85, 1.0), 132)
	_action_button("pause", "II", Vector2(1830, 60), Color(0.85, 0.85, 0.85), 76)


func _circle(center: Vector2, radius: float, color: Color, parent: Control) -> Panel:
	var panel := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(int(radius))
	style.border_color = Color(1, 1, 1, 0.18)
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.size = Vector2(radius * 2.0, radius * 2.0)
	panel.position = center - Vector2(radius, radius)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _action_button(action: String, label: String, center: Vector2, color: Color, size: int = BUTTON_SIZE) -> void:
	var button := Button.new()
	button.text = label
	button.add_theme_font_size_override("font_size", 34)
	button.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.10, 0.12, 0.55)
	style.border_color = color
	style.set_border_width_all(3)
	style.set_corner_radius_all(size / 2)
	button.add_theme_stylebox_override("normal", style)
	var pressed_style := style.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(color.r, color.g, color.b, 0.55)
	button.add_theme_stylebox_override("pressed", pressed_style)
	button.add_theme_stylebox_override("hover", style)
	button.size = Vector2(size, size)
	button.position = center - Vector2(size * 0.5, size * 0.5)
	button.focus_mode = Control.FOCUS_NONE
	button.button_down.connect(func(): Input.action_press(action))
	button.button_up.connect(func(): Input.action_release(action))
	button.mouse_exited.connect(func(): Input.action_release(action))
	add_child(button)


func _on_pad_input(event: InputEvent) -> void:
	if GameManager.is_paused() or GameManager.is_modal_open():
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.x < 900 and _move_touch < 0:
				_move_touch = event.index
				_move_origin = event.position
				_knob.position = event.position - _knob.size * 0.5
			elif _look_touch < 0:
				_look_touch = event.index
				_look_origin = event.position
		else:
			if event.index == _move_touch:
				_move_touch = -1
				InputManager.virtual_move = Vector2.ZERO
				_knob.position = MOVE_CENTER - _knob.size * 0.5
			if event.index == _look_touch:
				_look_touch = -1
				_look_active = false
				InputManager.virtual_look = Vector2.ZERO
	elif event is InputEventScreenDrag:
		if event.index == _move_touch:
			var offset: Vector2 = (event.position - _move_origin) / STICK_RADIUS
			if offset.length() > 1.0:
				offset = offset.normalized()
			InputManager.virtual_move = offset
			_knob.position = _move_origin + offset * STICK_RADIUS - _knob.size * 0.5
		elif event.index == _look_touch:
			var look_delta: Vector2 = event.relative / 34.0
			InputManager.virtual_look = Vector2(clampf(look_delta.x, -1.0, 1.0), clampf(look_delta.y, -1.0, 1.0))
			_look_active = true


func _process(delta: float) -> void:
	if _look_touch >= 0 and _look_active:
		InputManager.virtual_look = InputManager.virtual_look.lerp(Vector2.ZERO, delta * 14.0)
		if InputManager.virtual_look.length() < 0.02:
			InputManager.virtual_look = Vector2.ZERO


func _exit_tree() -> void:
	InputManager.touch_active = false
	InputManager.virtual_move = Vector2.ZERO
	InputManager.virtual_look = Vector2.ZERO
