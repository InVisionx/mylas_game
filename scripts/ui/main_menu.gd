class_name MainMenu
extends Control
## Title screen: clock in, pick a night, read the notebook, change settings.

var _main_page: VBoxContainer
var _shift_page: VBoxContainer
var _settings_page: VBoxContainer
var _title: Label
var _subtitle: Label
var _notebook: NotebookUI


func _ready() -> void:
	UIKit.full_rect(self)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_tree().paused = false
	GameManager.set_paused(false)
	_build()
	AudioManager.set_tension(1)
	_show_page("main")


func _build() -> void:
	var background := ColorRect.new()
	background.color = Color(0.015, 0.02, 0.026)
	UIKit.full_rect(background)
	add_child(background)

	var glow := ColorRect.new()
	glow.color = Color(0.06, 0.13, 0.15, 0.55)
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_bottom = -540
	add_child(glow)

	var vignette := ColorRect.new()
	UIKit.full_rect(vignette)
	var material := ShaderMaterial.new()
	material.shader = load("res://shaders/vignette.gdshader")
	material.set_shader_parameter("strength", 0.85)
	vignette.material = material
	add_child(vignette)

	var column := UIKit.vbox(8)
	column.set_anchors_preset(Control.PRESET_CENTER_LEFT)
	column.position = Vector2(160, -360)
	column.custom_minimum_size = Vector2(700, 760)
	add_child(column)

	_title = UIKit.label("NIGHT SHIFT", 92, Color(0.92, 0.97, 0.98))
	column.add_child(_title)
	_subtitle = UIKit.label("NOT HUMAN", 52, Color(0.55, 0.90, 0.80))
	column.add_child(_subtitle)
	var tagline := UIKit.label("Scan the groceries. Count the fingers. Keep the door closed.", 28, UIKit.TEXT_DIM)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(tagline)
	column.add_child(UIKit.spacer(24))

	_main_page = UIKit.vbox(10)
	_shift_page = UIKit.vbox(8)
	_settings_page = UIKit.vbox(8)
	column.add_child(_main_page)
	column.add_child(_shift_page)
	column.add_child(_settings_page)

	var build_label := UIKit.label("Five nights · endless overtime · offline save", 20, Color(0.35, 0.4, 0.43))
	build_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	build_label.position = Vector2(36, -44)
	add_child(build_label)

	_notebook = NotebookUI.new()
	_notebook.name = "Notebook"
	add_child(_notebook)

	_build_main()
	_build_shifts()
	_build_settings()


func _build_main() -> void:
	var unlocked := GameManager.unlocked_shift()
	var progress := int(GameManager.profile.get("shifts_completed", 0))
	var continue_label := "CLOCK IN — NIGHT %d" % unlocked
	if progress >= GameData.shift_count():
		continue_label = "CLOCK IN — ENDLESS"
	var continue_button := UIKit.button(continue_label, 36)
	continue_button.pressed.connect(_on_continue)
	_main_page.add_child(continue_button)

	var select := UIKit.button("SHIFT SELECT", 32)
	select.pressed.connect(_show_page.bind("shifts"))
	_main_page.add_child(select)

	var notes := UIKit.button("NOTEBOOK", 32)
	notes.pressed.connect(func(): _notebook.open())
	_main_page.add_child(notes)

	var settings := UIKit.button("SETTINGS", 32)
	settings.pressed.connect(_show_page.bind("settings"))
	_main_page.add_child(settings)

	var quit := UIKit.button("QUIT", 32)
	quit.pressed.connect(func(): get_tree().quit())
	_main_page.add_child(quit)


func _build_shifts() -> void:
	var header := UIKit.label("WHERE DO YOU WANT TO WORK?", 24, UIKit.TEXT_DIM)
	_shift_page.add_child(header)
	for shift in GameData.shifts:
		var index := int(shift.get("index", 1))
		var unlocked := index <= GameManager.unlocked_shift()
		var completed := index <= int(GameManager.profile.get("shifts_completed", 0))
		var suffix := "  [DONE]" if completed else ("  [LOCKED]" if not unlocked else "")
		var label := "%s — %s%s" % [str(shift.get("name", "")), str(shift.get("title", "")), suffix]
		var button := UIKit.button(label, 24)
		button.disabled = not unlocked
		button.pressed.connect(_start_night.bind(index))
		_shift_page.add_child(button)
	var endless_button := UIKit.button("ENDLESS OVERTIME", 24)
	endless_button.disabled = not GameManager.is_endless_unlocked()
	endless_button.pressed.connect(func(): GameManager.start_endless(1))
	_shift_page.add_child(endless_button)
	var back := UIKit.button("BACK", 26)
	back.pressed.connect(_show_page.bind("main"))
	_shift_page.add_child(back)


func _build_settings() -> void:
	var header := UIKit.label("SETTINGS", 24, UIKit.TEXT_DIM)
	_settings_page.add_child(header)

	var quality := UIKit.button("QUALITY: %s" % SettingsManager.quality_name().to_upper(), 24)
	quality.pressed.connect(func():
		var next := (int(SettingsManager.graphics["quality"]) + 1) % 3
		SettingsManager.set_graphics_value("quality", next)
		quality.text = "QUALITY: %s" % SettingsManager.quality_name().to_upper()
	)
	_settings_page.add_child(quality)

	var fps := UIKit.button("FRAME RATE: %d" % int(SettingsManager.graphics["fps_cap"]), 24)
	fps.pressed.connect(func():
		var next := 30 if int(SettingsManager.graphics["fps_cap"]) == 60 else 60
		SettingsManager.set_graphics_value("fps_cap", next)
		fps.text = "FRAME RATE: %d" % next
	)
	_settings_page.add_child(fps)

	var flash := UIKit.button("FLASHING: %s" % ("REDUCED" if SettingsManager.horror["reduced_flash"] else "FULL"), 24)
	flash.pressed.connect(func():
		var next := not bool(SettingsManager.horror["reduced_flash"])
		SettingsManager.set_horror_value("reduced_flash", next)
		flash.text = "FLASHING: %s" % ("REDUCED" if next else "FULL")
	)
	_settings_page.add_child(flash)

	var sensitivity := UIKit.button("LOOK SENSITIVITY: %.2f" % float(SettingsManager.controls["sensitivity"]), 24)
	sensitivity.pressed.connect(func():
		var next: float = float(SettingsManager.controls["sensitivity"]) + 0.15
		if next > 2.05:
			next = 0.55
		SettingsManager.set_control_value("sensitivity", next)
		sensitivity.text = "LOOK SENSITIVITY: %.2f" % next
	)
	_settings_page.add_child(sensitivity)

	var invert := UIKit.button("INVERT LOOK Y: %s" % ("ON" if SettingsManager.controls["invert_y"] else "OFF"), 24)
	invert.pressed.connect(func():
		var next := not bool(SettingsManager.controls["invert_y"])
		SettingsManager.set_control_value("invert_y", next)
		invert.text = "INVERT LOOK Y: %s" % ("ON" if next else "OFF")
	)
	_settings_page.add_child(invert)

	var back := UIKit.button("BACK", 26)
	back.pressed.connect(_show_page.bind("main"))
	_settings_page.add_child(back)


func _show_page(page: String) -> void:
	_main_page.visible = page == "main"
	_shift_page.visible = page == "shifts"
	_settings_page.visible = page == "settings"
	_subtitle.text = "NOT HUMAN" if page == "main" else ("CHOOSE YOUR SHIFT" if page == "shifts" else "SETTINGS")
	var page_node: VBoxContainer = _main_page
	if page == "shifts":
		page_node = _shift_page
	elif page == "settings":
		page_node = _settings_page
	for child in page_node.get_children():
		if child is Button and not (child as Button).disabled:
			(child as Button).grab_focus()
			break


func _on_continue() -> void:
	if int(GameManager.profile.get("shifts_completed", 0)) >= GameData.shift_count():
		GameManager.start_endless(1)
	else:
		GameManager.start_story_shift(GameManager.unlocked_shift())


func _start_night(index: int) -> void:
	GameManager.start_story_shift(index)
