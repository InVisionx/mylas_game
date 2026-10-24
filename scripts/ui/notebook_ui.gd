class_name NotebookUI
extends CanvasLayer
## The cashier's notebook: every anomaly you have ever caught, plus the hints
## that help you catch the next one.

var _panel: PanelContainer
var _entries: VBoxContainer
var _stats: Label
var _open := false


func _ready() -> void:
	layer = 40
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("notebook")
	_build()
	visible = false
	Events.notebook_updated.connect(_refresh)

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
	GameManager.open_modal("notebook")
	AudioManager.ui("ui_select")
	_refresh()


func close() -> void:
	if not _open:
		return
	_open = false
	visible = false
	GameManager.close_modal("notebook")
	AudioManager.ui("ui_back")


func _build() -> void:
	var root := Control.new()
	UIKit.full_rect(root)
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.012, 0.016, 0.9)
	UIKit.full_rect(dim)
	root.add_child(dim)

	_panel = UIKit.panel_container(Color(0.05, 0.055, 0.065, 0.97), UIKit.BORDER)
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.position = Vector2(-680, -450)
	_panel.custom_minimum_size = Vector2(1360, 900)
	root.add_child(_panel)

	var box := UIKit.vbox(10)
	_panel.add_child(box)
	var title := UIKit.label("INSPECTION NOTEBOOK", 44, UIKit.TEXT)
	box.add_child(title)
	_stats = UIKit.label("", 26, UIKit.TEXT_DIM)
	box.add_child(_stats)
	box.add_child(UIKit.separator())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(scroll)
	_entries = UIKit.vbox(8)
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_entries)

	var close_button := UIKit.button("CLOSE  [Y / Esc]", 30)
	close_button.pressed.connect(close)
	box.add_child(close_button)


func _process(_delta: float) -> void:
	if _open:
		# Keep the lease alive while the panel is open.
		GameManager.hold_input("notebook")
		if InputManager.is_just_pressed("cancel"):
			close()
		if InputManager.is_just_pressed("notebook"):
			close()


func _refresh() -> void:
	if _entries == null:
		return
	for child in _entries.get_children():
		child.queue_free()
	var discovered: Array = GameManager.profile.get("discovered_anomalies", [])
	var stats: Dictionary = GameManager.profile.get("stats", {})
	_stats.text = "Clues recorded: %d of %d     ·     Customers served: %d     ·     Entities refused: %d" % [
		discovered.size(), GameData.anomalies.size(),
		int(stats.get("customers_served", 0)), int(stats.get("entities_rejected", 0)),
	]
	if discovered.is_empty():
		_entries.add_child(UIKit.label("Nothing recorded yet. Inspect a customer and hold on a body part until something catches your eye.", 24, UIKit.TEXT_DIM))
		return
	for anomaly in GameData.anomalies:
		var id := str(anomaly.get("id", ""))
		var known := discovered.has(id)
		var row := UIKit.hbox(12)
		var marker := UIKit.label("●" if known else "○", 28, UIKit.ACCENT if known else Color(0.3, 0.33, 0.36))
		marker.custom_minimum_size = Vector2(28, 0)
		row.add_child(marker)
		var text := UIKit.label("%s — %s" % [str(anomaly.get("label", "")), str(anomaly.get("category", "")).to_upper()], 28, UIKit.TEXT if known else Color(0.36, 0.40, 0.43))
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text)
		var focus := UIKit.label(str(anomaly.get("focus", "")).to_upper(), 24, UIKit.TEXT_DIM)
		row.add_child(focus)
		_entries.add_child(row)
		if known:
			var description := UIKit.label("      " + str(anomaly.get("description", "")), 24, UIKit.TEXT_DIM)
			description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_entries.add_child(description)
		else:
			var hint := UIKit.label("      " + str(anomaly.get("hint", "")), 23, Color(0.45, 0.5, 0.53))
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_entries.add_child(hint)
