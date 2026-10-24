class_name PauseMenu
extends CanvasLayer
## Pause, settings and control rebinding. Fully navigable with D-pad + A.

var _root: Control
var _main_page: VBoxContainer
var _settings_page: VBoxContainer
var _controls_page: VBoxContainer
var _diagnostics_page: VBoxContainer
var _title: Label
var _open := false
var _diag_live: Label
var _diag_note: Label
var _diag_tail: Label
var _diag_timer := 0.0


func _ready() -> void:
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("pause_menu")
	_build()
	Events.request_pause.connect(_on_pause_requested)
	visible = false


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	GameManager.set_paused(true)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_show_page("main")
	AudioManager.ui("ui_select")


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	GameManager.set_paused(false)
	if not (DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")):
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	AudioManager.ui("ui_back")


func _on_pause_requested(paused: bool) -> void:
	if paused:
		visible = true
		_open = true
	elif not paused:
		visible = _open


func _process(_delta: float) -> void:
	if _open and InputManager.is_just_pressed("pause"):
		close()
	if _open and _diagnostics_page != null and _diagnostics_page.visible:
		_diag_timer -= _delta
		if _diag_timer <= 0.0:
			_diag_timer = 0.5
			_refresh_diagnostics()


func _build() -> void:
	_root = Control.new()
	UIKit.full_rect(_root)
	add_child(_root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.82)
	UIKit.full_rect(dim)
	_root.add_child(dim)

	var panel := UIKit.panel_container(Color(0.045, 0.055, 0.07, 0.97), UIKit.BORDER)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = Vector2(-470, -420)
	panel.custom_minimum_size = Vector2(940, 840)
	_root.add_child(panel)

	var box := UIKit.vbox(14)
	panel.add_child(box)
	_title = UIKit.label("PAUSED", 48, UIKit.TEXT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	box.add_child(UIKit.separator())

	_main_page = UIKit.vbox(10)
	_settings_page = UIKit.vbox(8)
	_controls_page = UIKit.vbox(6)
	_diagnostics_page = UIKit.vbox(8)
	for page in [_main_page, _settings_page, _controls_page, _diagnostics_page]:
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(page)

	var hint := UIKit.label("D-Pad / Arrows navigate · A / Enter select · Menu / Esc resume", 20, UIKit.TEXT_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(hint)

	_build_main()
	_build_settings()
	_build_controls()
	_build_diagnostics()


func _build_main() -> void:
	for child in _main_page.get_children():
		child.queue_free()
	if Diagnostics.previous_session_crashed:
		var warn := UIKit.label("Previous session ended unexpectedly — see DIAGNOSTICS", 22, UIKit.BAD)
		warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_main_page.add_child(warn)
	_main_page.add_child(UIKit.button("RESUME SHIFT", 30))
	var resume := _main_page.get_child(_main_page.get_child_count() - 1) as Button
	resume.pressed.connect(close)

	_add_page_button("SETTINGS", "settings")
	_add_page_button("CONTROLS & BINDINGS", "controls")
	_add_page_button("DIAGNOSTICS", "diagnostics")
	var notebook_button := UIKit.button("NOTEBOOK", 30)
	notebook_button.pressed.connect(_open_notebook)
	_main_page.add_child(notebook_button)
	_main_page.add_child(UIKit.spacer(10))
	var abandon := UIKit.button("ABANDON SHIFT", 30)
	abandon.pressed.connect(_abandon_shift)
	_main_page.add_child(abandon)
	var menu := UIKit.button("SAVE & QUIT TO MENU", 30)
	menu.pressed.connect(_quit_to_menu)
	_main_page.add_child(menu)


func _add_page_button(text: String, page: String) -> void:
	var button := UIKit.button(text, 30)
	button.pressed.connect(_show_page.bind(page))
	_main_page.add_child(button)


func _show_page(page: String) -> void:
	_main_page.visible = page == "main"
	_settings_page.visible = page == "settings"
	_controls_page.visible = page == "controls"
	_diagnostics_page.visible = page == "diagnostics"
	match page:
		"settings":
			_title.text = "SETTINGS"
			_refresh_settings_labels()
		"controls":
			_title.text = "CONTROLS"
			_refresh_bindings()
		"diagnostics":
			_title.text = "DIAGNOSTICS"
			_refresh_diagnostics()
		_:
			_title.text = "PAUSED"
	var target_page: VBoxContainer = _main_page
	if page == "settings":
		target_page = _settings_page
	elif page == "controls":
		target_page = _controls_page
	elif page == "diagnostics":
		target_page = _diagnostics_page
	var first := _first_focusable(target_page)
	if first != null:
		first.grab_focus()


func _first_focusable(page: Node) -> Control:
	for child in page.get_children():
		if child is Control and (child as Control).focus_mode != Control.FOCUS_NONE:
			return child
		if child is Control:
			var nested := _first_focusable(child)
			if nested != null:
				return nested
	return null


func _build_settings() -> void:
	_settings_page.visible = false
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_settings_page.add_child(scroll)
	var box := UIKit.vbox(8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	box.add_child(_section("AUDIO"))
	box.add_child(_slider_row("Master volume", "audio", "master", 0.0, 1.0, 0.05))
	box.add_child(_slider_row("Sound effects", "audio", "sfx", 0.0, 1.0, 0.05))
	box.add_child(_slider_row("Ambience", "audio", "ambience", 0.0, 1.0, 0.05))

	box.add_child(_section("GRAPHICS"))
	box.add_child(_option_row("Quality", ["Low", "Medium", "High"], "quality"))
	box.add_child(_option_row("Frame rate", ["30 FPS", "60 FPS", "Unlimited"], "fps_cap", [30, 60, 0]))
	box.add_child(_slider_row("Field of view", "graphics", "fov", 60.0, 95.0, 1.0))

	box.add_child(_section("CONTROLS"))
	box.add_child(_slider_row("Look sensitivity", "controls", "sensitivity", 0.3, 2.5, 0.05))
	box.add_child(_slider_row("Vertical sensitivity", "controls", "sensitivity_y", 0.3, 2.5, 0.05))
	box.add_child(_slider_row("Stick dead zone", "controls", "deadzone", 0.05, 0.4, 0.01))
	box.add_child(_check_row("Invert look Y", "controls", "invert_y"))
	box.add_child(_check_row("Invert look X", "controls", "invert_x"))
	box.add_child(_check_row("Vibration", "controls", "vibration"))
	box.add_child(_check_row("Fast checkout (LB scans the belt)", "controls", "fast_checkout"))

	box.add_child(_section("HORROR ACCESSIBILITY"))
	box.add_child(_check_row("Reduce flashing and stingers", "horror", "reduced_flash"))
	box.add_child(_check_row("Quieter horror audio", "horror", "reduced_audio"))

	var back := UIKit.button("BACK", 28)
	back.pressed.connect(_show_page.bind("main"))
	_settings_page.add_child(back)


func _section(text: String) -> Label:
	var label := UIKit.label(text, 26, UIKit.ACCENT)
	label.custom_minimum_size = Vector2(0, 40)
	return label


func _slider_row(label_text: String, section: String, key: String, min_value: float, max_value: float, step: float) -> HBoxContainer:
	var row := UIKit.hbox(14)
	var label := UIKit.label(label_text, 30, UIKit.TEXT)
	label.custom_minimum_size = Vector2(500, 0)
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	var source: Dictionary = SettingsManager.get(section)
	slider.value = float(source.get(key, min_value))
	slider.custom_minimum_size = Vector2(290, 44)
	slider.focus_mode = Control.FOCUS_ALL
	var value_label := UIKit.label(_format_float(slider.value), 26, UIKit.TEXT_DIM)
	value_label.custom_minimum_size = Vector2(80, 0)
	slider.value_changed.connect(func(value: float):
		value_label.text = _format_float(value)
		if section == "audio":
			SettingsManager.set_audio_value(key, value)
		elif section == "graphics":
			SettingsManager.set_graphics_value(key, value)
		else:
			SettingsManager.set_control_value(key, value)
	)
	row.add_child(slider)
	row.add_child(value_label)
	return row


func _option_row(label_text: String, options: Array, key: String, values: Array = []) -> HBoxContainer:
	var row := UIKit.hbox(14)
	var label := UIKit.label(label_text, 30, UIKit.TEXT)
	label.custom_minimum_size = Vector2(500, 0)
	row.add_child(label)
	var picker := OptionButton.new()
	picker.add_theme_font_size_override("font_size", 26)
	picker.custom_minimum_size = Vector2(290, 44)
	picker.focus_mode = Control.FOCUS_ALL
	for option in options:
		picker.add_item(str(option))
	var current_value: int = int(SettingsManager.graphics.get(key, 0))
	if values.is_empty():
		picker.selected = clampi(current_value, 0, options.size() - 1)
	else:
		picker.selected = maxi(values.find(current_value), 0)
	picker.item_selected.connect(func(index: int):
		var value := int(values[index]) if not values.is_empty() else index
		SettingsManager.set_graphics_value(key, value)
	)
	row.add_child(picker)
	return row


func _check_row(label_text: String, section: String, key: String) -> CheckBox:
	var box := CheckBox.new()
	box.text = label_text
	box.add_theme_font_size_override("font_size", 30)
	box.focus_mode = Control.FOCUS_ALL
	var source: Dictionary = SettingsManager.get(section)
	box.button_pressed = bool(source.get(key, false))
	box.toggled.connect(func(pressed: bool):
		if section == "horror":
			SettingsManager.set_horror_value(key, pressed)
		else:
			SettingsManager.set_control_value(key, pressed)
	)
	return box


func _format_float(value: float) -> String:
	if value <= 3.0:
		return "%.2f" % value
	return "%d" % int(value)


func _refresh_settings_labels() -> void:
	pass


func _build_controls() -> void:
	_controls_page.visible = false
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_controls_page.add_child(scroll)
	var list := UIKit.vbox(4)
	list.name = "BindingList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)

	var hint := UIKit.label("Select an action, then press any key or button. Esc cancels.", 24, UIKit.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_controls_page.add_child(hint)

	var reset := UIKit.button("RESET TO DEFAULTS", 26)
	reset.pressed.connect(func():
		InputManager.reset_bindings()
		_refresh_bindings()
	)
	_controls_page.add_child(reset)
	var back := UIKit.button("BACK", 26)
	back.pressed.connect(_show_page.bind("main"))
	_controls_page.add_child(back)


func _refresh_bindings() -> void:
	var list := _controls_page.find_child("BindingList", true, false) as VBoxContainer
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()
	var actions := ["move_forward", "move_back", "move_left", "move_right", "interact", "cancel", "inspect", "notebook", "approve", "reject", "sprint", "crouch", "zoom", "pause", "focus_next", "focus_prev"]
	for action in actions:
		var row := UIKit.hbox(10)
		var label := UIKit.label(str(action).replace("_", " ").capitalize(), 28, UIKit.TEXT)
		label.custom_minimum_size = Vector2(420, 0)
		row.add_child(label)
		var button := UIKit.button(InputManager.binding_label(action), 26)
		button.custom_minimum_size = Vector2(300, 50)
		button.pressed.connect(func():
			button.text = "Press a key..."
			InputManager.start_rebind(action)
		)
		row.add_child(button)
		list.add_child(row)


func _build_diagnostics() -> void:
	_diagnostics_page.visible = false
	_diag_note = UIKit.label("Live engine counters and the tail of the flight recorder.", 24, UIKit.TEXT_DIM)
	_diag_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_diagnostics_page.add_child(_diag_note)

	_diag_live = UIKit.label("", 24, UIKit.TEXT)
	_diagnostics_page.add_child(_diag_live)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 280)
	_diagnostics_page.add_child(scroll)
	_diag_tail = UIKit.label("", 18, UIKit.TEXT_DIM)
	_diag_tail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_diag_tail)

	var row := UIKit.hbox(10)
	var copy := UIKit.button("COPY LOG", 26)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(Diagnostics.tail(40))
		_diag_note.text = "Log copied to clipboard."
		_diag_note.add_theme_color_override("font_color", UIKit.ACCENT)
	)
	row.add_child(copy)
	var back := UIKit.button("BACK", 26)
	back.pressed.connect(_show_page.bind("main"))
	row.add_child(back)
	_diagnostics_page.add_child(row)

	var path := UIKit.label("log file: %s" % Diagnostics.log_path_display(), 18, UIKit.TEXT_DIM)
	_diagnostics_page.add_child(path)


func _refresh_diagnostics() -> void:
	if _diag_live == null:
		return
	_diag_live.text = Diagnostics.live_summary()
	_diag_tail.text = "[engine]\n%s\n\n[events]\n%s" % [Diagnostics.engine_tail(10), Diagnostics.tail(10)]
	if Diagnostics.previous_session_crashed:
		_diag_note.text = "The previous session did not shut down cleanly. The log below may show where it stopped."
		_diag_note.add_theme_color_override("font_color", UIKit.BAD)


func _open_notebook() -> void:
	var notebooks := get_tree().get_nodes_in_group("notebook")
	if notebooks.is_empty():
		return
	var notebook = notebooks[0]
	if notebook.has_method("open"):
		notebook.call("open")


func _abandon_shift() -> void:
	_close_state()
	GameManager.abort_shift()


func _quit_to_menu() -> void:
	_close_state()
	GameManager.return_to_menu()


func _close_state() -> void:
	_open = false
	visible = false
	get_tree().paused = false
