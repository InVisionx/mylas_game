class_name ShiftReport
extends CanvasLayer
## End-of-shift paperwork. Also the place where a failed night is retried.

var _panel: PanelContainer
var _title: Label
var _subtitle: Label
var _rows: VBoxContainer
var _reason: Label
var _buttons: HBoxContainer
var _last_report: Dictionary = {}


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("shift_report")
	Events.shift_ended.connect(_on_shift_ended)
	_build()
	visible = false


func _build() -> void:
	var root := Control.new()
	UIKit.full_rect(root)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.005, 0.008, 0.01, 0.94)
	UIKit.full_rect(dim)
	root.add_child(dim)

	_panel = UIKit.panel_container(Color(0.05, 0.055, 0.068, 0.98), UIKit.BORDER)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-560, -400)
	_panel.custom_minimum_size = Vector2(1120, 800)
	root.add_child(_panel)

	var box := UIKit.vbox(12)
	_panel.add_child(box)
	_title = UIKit.label("SHIFT COMPLETE", 56, UIKit.ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_subtitle = UIKit.label("", 30, UIKit.TEXT_DIM)
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_subtitle)
	box.add_child(UIKit.separator())
	_rows = UIKit.vbox(6)
	box.add_child(_rows)
	_reason = UIKit.label("", 28, UIKit.BAD)
	_reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_reason)
	box.add_child(UIKit.spacer(16))
	_buttons = UIKit.hbox(16)
	_buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_buttons)


func _on_shift_ended(report: Dictionary) -> void:
	_last_report = report
	visible = true
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_title.text = "SHIFT FAILED" if bool(report.get("failed", false)) else "SHIFT COMPLETE"
	_title.add_theme_color_override("font_color", UIKit.BAD if bool(report.get("failed", false)) else UIKit.ACCENT)
	_subtitle.text = "%s — %s" % [str(report.get("name", "Shift")), str(report.get("title", ""))]
	_reason.text = str(report.get("reason", ""))
	AudioManager.play("register_open", -8.0)
	if bool(report.get("failed", false)):
		AudioManager.play("stinger_soft", -14.0)

	_clear_rows()
	_add_row("Customers served", "%d" % int(report.get("served", 0)))
	_add_row("Correct decisions", "%d" % int(report.get("correct", 0)), UIKit.ACCENT)
	_add_row("Mistakes", "%d" % int(report.get("wrong", 0)), UIKit.BAD if int(report.get("wrong", 0)) > 0 else UIKit.TEXT)
	_add_row("Accuracy", "%.0f%%" % float(report.get("accuracy", 0.0)))
	_add_row("Entities refused", "%d" % int(report.get("entities_rejected", 0)))
	_add_row("Entities let through", "%d" % int(report.get("entities_approved", 0)), UIKit.BAD if int(report.get("entities_approved", 0)) > 0 else UIKit.TEXT)
	_add_row("Wages collected", GameData.price_string(int(report.get("money", 0))), UIKit.ACCENT)
	_add_row("Fines", "-%s" % GameData.price_string(int(report.get("penalty", 0))), UIKit.BAD)
	_add_row("New clues", "%d" % (report.get("clues", []) as Array).size())

	for child in _buttons.get_children():
		child.queue_free()
	var continue_button := UIKit.button(_continue_label(), 34)
	continue_button.pressed.connect(_continue)
	_buttons.add_child(continue_button)
	var menu_button := UIKit.button("MAIN MENU", 34)
	menu_button.pressed.connect(_to_menu)
	_buttons.add_child(menu_button)
	continue_button.grab_focus()


func _clear_rows() -> void:
	for child in _rows.get_children():
		child.queue_free()


func _add_row(label_text: String, value_text: String, color: Color = UIKit.TEXT) -> void:
	var row := UIKit.hbox(20)
	var label := UIKit.label(label_text, 30, UIKit.TEXT_DIM)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var value := UIKit.label(value_text, 30, color)
	row.add_child(value)
	_rows.add_child(row)


func _continue_label() -> String:
	if bool(_last_report.get("failed", false)):
		return "TRY AGAIN"
	if str(_last_report.get("mode", "story")) == "endless":
		return "NEXT ROUND"
	if int(_last_report.get("unlocked_next", 0)) > 0:
		return "NEXT NIGHT"
	return "ENDLESS MODE UNLOCKED"


func _continue() -> void:
	visible = false
	get_tree().paused = false
	GameManager.continue_after_report()


func _to_menu() -> void:
	visible = false
	get_tree().paused = false
	GameManager.return_to_menu()


func _process(_delta: float) -> void:
	if not visible:
		return
	if InputManager.is_just_pressed("pause"):
		_to_menu()
