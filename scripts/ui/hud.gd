class_name GameHUD
extends CanvasLayer
## Everything the player reads during a shift. Built in code so the layout can
## be tuned in one place and stays readable at 1080p on a small screen.

var player: PlayerController
var shift: ShiftManager
var checkout: CheckoutManager
var inspection: InspectionManager
var builder: StoreBuilder
var notebook: Node

var root: Control
var shift_label: Label
var time_label: Label
var served_label: Label
var money_label: Label
var clue_label: Label
var prompt_label: Label
var subtitle_label: Label
var reticle: Control
var toast_box: VBoxContainer
var inspect_panel: PanelContainer
var inspect_focus: Label
var inspect_text: Label
var inspect_bar: ProgressBar
var checkout_panel: PanelContainer
var checkout_label: Label
var checkout_hint: Label
var action_hint: Label
var dialogue_panel: PanelContainer
var dialogue_name: Label
var dialogue_text: Label
var dialogue_questions: VBoxContainer
var flash_rect: ColorRect

var _dialogue_customer: Customer = null
var _subtitle_timer := 0.0
var _last_prompt := ""
var _touch_controls: Node = null


func setup(refs: Dictionary) -> void:
	player = refs.get("player")
	shift = refs.get("shift")
	checkout = refs.get("checkout")
	inspection = refs.get("inspection")
	builder = refs.get("builder")
	notebook = refs.get("notebook")


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	Events.notify.connect(_on_notify)
	Events.dialogue_line.connect(_on_dialogue_line)
	Events.inspection_started.connect(_on_inspection_started)
	Events.inspection_ended.connect(_on_inspection_ended)
	Events.inspection_focus_changed.connect(_on_focus_changed)
	Events.inspection_progress.connect(_on_inspection_progress)
	Events.jumpscare_started.connect(_on_jumpscare_started)
	Events.jumpscare_finished.connect(_on_jumpscare_finished)
	Events.money_changed.connect(_on_money_changed)
	Events.customer_count_changed.connect(_on_counts_changed)
	Events.checkout_ready.connect(_on_checkout_ready)
	Events.notebook_updated.connect(_refresh_clue_count)
	if shift != null:
		shift.dialogue_requested.connect(_open_dialogue)
	if checkout != null:
		checkout.scan_progress.connect(_on_scan_progress)
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		_spawn_touch_controls()
	_refresh_clue_count()
	UpdateManager.update_available.connect(func(_info): UpdateManager.notify_once())
	UpdateManager.notify_once()


func _build() -> void:
	root = Control.new()
	UIKit.full_rect(root)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var vignette := ColorRect.new()
	UIKit.full_rect(vignette)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vignette_material := ShaderMaterial.new()
	vignette_material.shader = load("res://shaders/vignette.gdshader")
	vignette.material = vignette_material
	root.add_child(vignette)

	_build_top_bar()
	_build_prompt()
	_build_reticle()
	_build_toasts()
	_build_inspection_panel()
	_build_checkout_panel()
	_build_dialogue_panel()
	_build_flash()
	_build_action_hint()


func _build_top_bar() -> void:
	var panel := UIKit.panel_container(Color(0.04, 0.05, 0.06, 0.72), Color(0.35, 0.48, 0.5, 0.4))
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(24, 20)
	panel.custom_minimum_size = Vector2(430, 0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	var box := UIKit.vbox(4)
	panel.add_child(box)
	shift_label = UIKit.label("NIGHT 1 - TRAINING SHIFT", 36, UIKit.TEXT)
	box.add_child(shift_label)
	var row := UIKit.hbox(26)
	box.add_child(row)
	time_label = UIKit.label("00:00", 32, UIKit.WARN)
	row.add_child(time_label)
	served_label = UIKit.label("SERVED 0/0", 32, UIKit.TEXT_DIM)
	row.add_child(served_label)
	money_label = UIKit.label("$0", 32, UIKit.ACCENT)
	row.add_child(money_label)

	var clue_panel := UIKit.panel_container(Color(0.04, 0.05, 0.06, 0.72), Color(0.35, 0.48, 0.5, 0.4))
	clue_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clue_panel.position = Vector2(-300, 20)
	clue_panel.custom_minimum_size = Vector2(260, 0)
	clue_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(clue_panel)
	clue_label = UIKit.label("CLUES 0", 30, UIKit.ACCENT)
	clue_panel.add_child(clue_label)


func _build_prompt() -> void:
	prompt_label = UIKit.label("", 36, Color(0.95, 0.99, 1.0))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.position = Vector2(-420, -330)
	prompt_label.custom_minimum_size = Vector2(840, 40)
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(prompt_label)

	subtitle_label = UIKit.label("", 36, Color(1, 0.96, 0.86))
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	subtitle_label.position = Vector2(-520, -250)
	subtitle_label.custom_minimum_size = Vector2(1040, 90)
	subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(subtitle_label)


func _build_reticle() -> void:
	reticle = Control.new()
	reticle.set_anchors_preset(Control.PRESET_CENTER)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)
	var offsets := [Vector2(-4, 0), Vector2(4, 0), Vector2(0, -4), Vector2(0, 4)]
	for offset in offsets:
		var dot := ColorRect.new()
		dot.color = Color(0.9, 1.0, 0.98, 0.55)
		dot.size = Vector2(3, 3)
		dot.position = offset - Vector2(1.5, 1.5)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		reticle.add_child(dot)


func _build_toasts() -> void:
	toast_box = UIKit.vbox(6)
	toast_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_box.position = Vector2(-380, 24)
	toast_box.custom_minimum_size = Vector2(760, 0)
	toast_box.alignment = BoxContainer.ALIGNMENT_CENTER
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)


func _build_action_hint() -> void:
	action_hint = UIKit.label("", 24, UIKit.TEXT_DIM)
	action_hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	action_hint.position = Vector2(24, -54)
	action_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(action_hint)
	_refresh_action_hint()
	InputManager.input_device_changed.connect(func(_device): _refresh_action_hint())


func _build_flash() -> void:
	flash_rect = ColorRect.new()
	UIKit.full_rect(flash_rect)
	flash_rect.color = Color(0, 0, 0, 0)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(flash_rect)


func _build_inspection_panel() -> void:
	inspect_panel = UIKit.panel_container(Color(0.035, 0.045, 0.055, 0.9), Color(0.42, 0.58, 0.62, 0.55))
	inspect_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	inspect_panel.position = Vector2(-470, -210)
	inspect_panel.custom_minimum_size = Vector2(940, 0)
	inspect_panel.visible = false
	inspect_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(inspect_panel)

	var box := UIKit.vbox(8)
	inspect_panel.add_child(box)
	var header := UIKit.hbox(14)
	box.add_child(header)
	inspect_focus = UIKit.label("FACE / EXPRESSION", 32, UIKit.ACCENT)
	header.add_child(inspect_focus)
	var hint := UIKit.label("[< >] change focus   [LB] zoom   [B] done", 24, UIKit.TEXT_DIM)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(hint)
	inspect_bar = UIKit.progress_bar(UIKit.ACCENT)
	box.add_child(inspect_bar)
	inspect_text = UIKit.label("", 32, UIKit.TEXT)
	inspect_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspect_text.custom_minimum_size = Vector2(900, 60)
	box.add_child(inspect_text)


func _build_checkout_panel() -> void:
	checkout_panel = UIKit.panel_container(Color(0.04, 0.05, 0.06, 0.82), Color(0.42, 0.58, 0.62, 0.5))
	checkout_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	checkout_panel.position = Vector2(-430, -170)
	checkout_panel.custom_minimum_size = Vector2(400, 0)
	checkout_panel.visible = false
	checkout_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(checkout_panel)
	var box := UIKit.vbox(4)
	checkout_panel.add_child(box)
	checkout_label = UIKit.label("ITEMS 0/0   $0.00", 32, UIKit.TEXT)
	box.add_child(checkout_label)
	checkout_hint = UIKit.label("", 26, UIKit.TEXT_DIM)
	checkout_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(checkout_hint)


func _build_dialogue_panel() -> void:
	dialogue_panel = UIKit.panel_container(Color(0.03, 0.04, 0.05, 0.94), Color(0.42, 0.58, 0.62, 0.6))
	dialogue_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	dialogue_panel.position = Vector2(-520, -360)
	dialogue_panel.custom_minimum_size = Vector2(1040, 0)
	dialogue_panel.visible = false
	root.add_child(dialogue_panel)

	var box := UIKit.vbox(10)
	dialogue_panel.add_child(box)
	dialogue_name = UIKit.label("CUSTOMER", 32, UIKit.ACCENT)
	box.add_child(dialogue_name)
	dialogue_text = UIKit.label("...", 34, UIKit.TEXT)
	dialogue_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dialogue_text.custom_minimum_size = Vector2(1000, 70)
	box.add_child(dialogue_text)
	box.add_child(UIKit.separator())
	dialogue_questions = UIKit.vbox(6)
	box.add_child(dialogue_questions)


func _spawn_touch_controls() -> void:
	var script := load("res://scripts/ui/touch_controls.gd")
	if script == null:
		return
	var controls := CanvasLayer.new()
	controls.set_script(script)
	controls.name = "TouchControls"
	add_child(controls)
	_touch_controls = controls


# --- Runtime updates --------------------------------------------------------

func _process(delta: float) -> void:
	if shift != null:
		time_label.text = shift.remaining_time_string()
		if shift.time_left < 45.0:
			time_label.add_theme_color_override("font_color", UIKit.BAD if int(Time.get_ticks_msec() / 400) % 2 == 0 else UIKit.WARN)
		else:
			time_label.add_theme_color_override("font_color", UIKit.WARN)

	var checkout_visible := checkout != null and checkout.active and not GameManager.is_paused()
	checkout_panel.visible = checkout_visible
	if checkout_visible:
		var total := checkout.scanned_count + checkout.remaining_items()
		checkout_label.text = "ITEMS %d/%d   %s" % [checkout.scanned_count, total, GameData.price_string(checkout.total_cents)]
		if checkout.is_ready_for_decision():
			checkout_hint.text = "[RT] approve   |   [LT] reject"
			checkout_hint.add_theme_color_override("font_color", UIKit.ACCENT)
		else:
			checkout_hint.text = "Scan everything on the belt."
			checkout_hint.add_theme_color_override("font_color", UIKit.TEXT_DIM)

	if _subtitle_timer > 0.0:
		_subtitle_timer -= delta
		if _subtitle_timer <= 0.0:
			subtitle_label.text = ""

	if dialogue_panel != null and dialogue_panel.visible and InputManager.is_just_pressed("cancel"):
		close_dialogue()

	_update_prompt()
	_handle_actions()

	if _touch_controls != null:
		_touch_controls.visible = not InputManager.has_gamepad() and not GameManager.is_paused() and not GameManager.is_modal_open()


func _update_prompt() -> void:
	if player == null:
		return
	var prompt := ""
	if not GameManager.is_modal_open():
		prompt = player.current_prompt()
		if prompt.is_empty() and inspection != null and not inspection.active:
			var customer := _customer_in_front()
			if customer != null and customer.state == Customer.State.AT_COUNTER:
				prompt = "TALK TO %s   |   [X] INSPECT" % customer.full_name.to_upper()
	if prompt != _last_prompt:
		_last_prompt = prompt
		prompt_label.text = prompt


func _customer_in_front() -> Customer:
	if player == null:
		return null
	var forward := -player.camera.global_transform.basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var best: Customer = null
	var best_score := -1.0
	for node in get_tree().get_nodes_in_group("customers"):
		var customer := node as Customer
		if customer == null:
			continue
		var to_customer := customer.global_position - player.global_position
		to_customer.y = 0.0
		var distance := to_customer.length()
		if distance > 4.2:
			continue
		var alignment := forward.dot(to_customer.normalized())
		if alignment < 0.55:
			continue
		var score := alignment - distance * 0.05
		if score > best_score:
			best_score = score
			best = customer
	return best


func _handle_actions() -> void:
	if player == null:
		return
	if GameManager.is_paused():
		return
	if InputManager.is_just_pressed("pause"):
		_toggle_pause()
		return
	if GameManager.is_modal_open():
		return

	if InputManager.is_just_pressed("interact"):
		player.try_interact()
	if InputManager.is_just_pressed("inspect"):
		var customer := _customer_in_front()
		if customer != null and inspection != null and not inspection.active:
			inspection.begin(customer)
		else:
			Events.notify.emit("Nobody close enough to inspect.", "warn")
	if InputManager.is_just_pressed("approve") and shift != null:
		shift.approve_customer()
	if InputManager.is_just_pressed("reject") and shift != null:
		shift.reject_customer()
	if InputManager.is_just_pressed("notebook") and notebook != null and notebook.has_method("toggle"):
		notebook.call("toggle")
	if InputManager.is_just_pressed("zoom") and bool(SettingsManager.controls["fast_checkout"]) and checkout != null and checkout.active:
		checkout.scan_all()

	_update_zoom()


func _update_zoom() -> void:
	if inspection != null and inspection.active:
		return
	var held := InputManager.is_held("zoom")
	var base := float(SettingsManager.graphics.get("fov", 75.0))
	player.set_fov(base - (14.0 if held else 0.0))


func _toggle_pause() -> void:
	var menus := get_tree().get_nodes_in_group("pause_menu")
	if menus.is_empty():
		return
	var menu = menus[0]
	if menu.has_method("toggle"):
		menu.call("toggle")


func _refresh_action_hint() -> void:
	if action_hint == null:
		return
	if InputManager.last_device == "gamepad":
		action_hint.text = "LS move | RS look | A interact | X inspect | Y notes | RT approve | LT reject | Menu pause"
	else:
		action_hint.text = "WASD move | Mouse look | E interact | F inspect | Tab notes | Enter approve | Backspace reject | Esc pause"


func _refresh_clue_count() -> void:
	if clue_label:
		clue_label.text = "CLUES %d" % GameManager.discovered_count()


# --- Dialogue ---------------------------------------------------------------

func _open_dialogue(customer: Customer) -> void:
	if customer == null or not is_instance_valid(customer):
		return
	_dialogue_customer = customer
	dialogue_name.text = "%s  -  %s" % [customer.full_name.to_upper(), str(customer.personality.get("label", "")).to_upper()]
	dialogue_text.text = customer.greeting()
	dialogue_panel.visible = true
	GameManager.open_modal()
	AudioManager.ui("ui_select")
	_rebuild_questions()
	var first := _first_question_button()
	if first != null:
		first.grab_focus()


func close_dialogue() -> void:
	if not dialogue_panel.visible:
		return
	dialogue_panel.visible = false
	_dialogue_customer = null
	GameManager.close_modal()
	AudioManager.ui("ui_back")


func _rebuild_questions() -> void:
	for child in dialogue_questions.get_children():
		child.queue_free()
	for question in GameData.questions:
		var button := UIKit.button(str(question.get("label", "Ask")), 30)
		button.pressed.connect(_ask_question.bind(str(question.get("id", ""))))
		dialogue_questions.add_child(button)
	var leave := UIKit.button("Say nothing and step away", 30)
	leave.pressed.connect(close_dialogue)
	dialogue_questions.add_child(leave)


func _first_question_button() -> Button:
	for child in dialogue_questions.get_children():
		if child is Button:
			return child
	return null


func _ask_question(question_id: String) -> void:
	if _dialogue_customer == null or not is_instance_valid(_dialogue_customer):
		close_dialogue()
		return
	var line := _dialogue_customer.answer(question_id)
	dialogue_text.text = line
	AudioManager.ui("ui_select")
	_rebuild_questions()
	var first := _first_question_button()
	if first != null:
		first.grab_focus()


# --- Events -----------------------------------------------------------------

func _on_notify(text: String, tone: String) -> void:
	if toast_box == null:
		return
	var label := UIKit.label(text, 30, UIKit.color_for_tone(tone))
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	toast_box.add_child(label)
	while toast_box.get_child_count() > 4:
		var oldest := toast_box.get_child(0)
		toast_box.remove_child(oldest)
		oldest.queue_free()
	var tween := create_tween()
	tween.tween_interval(2.6)
	tween.tween_property(label, "modulate:a", 0.0, 0.8)
	tween.tween_callback(label.queue_free)


func _on_dialogue_line(speaker: String, text: String) -> void:
	if speaker == "INSPECTION":
		if inspect_text:
			inspect_text.text = text
		return
	subtitle_label.text = "%s: %s" % [speaker, text] if speaker != "SYSTEM" else text
	_subtitle_timer = 4.5


func _on_inspection_started(_customer_id: int) -> void:
	inspect_panel.visible = true
	reticle.visible = false
	prompt_label.visible = false
	inspect_bar.value = 0.0
	inspect_text.text = "Study them. Do not rush it."


func _on_inspection_ended() -> void:
	inspect_panel.visible = false
	reticle.visible = true
	prompt_label.visible = true


func _on_focus_changed(_focus: String, label: String) -> void:
	if inspect_focus:
		inspect_focus.text = label
		inspect_bar.value = 0.0


func _on_inspection_progress(ratio: float) -> void:
	if inspect_bar:
		inspect_bar.value = ratio


func _on_jumpscare_started(_kind: String) -> void:
	var intensity: float = SettingsManager.flash_scale()
	var tween := create_tween()
	tween.tween_property(flash_rect, "color", Color(0.75, 0.02, 0.02, 0.85 * intensity), 0.06)
	tween.tween_property(flash_rect, "color", Color(0, 0, 0, 0.0), 0.35)
	inspect_panel.visible = false
	checkout_panel.visible = false
	prompt_label.visible = false
	subtitle_label.text = ""


func _on_jumpscare_finished(_kind: String) -> void:
	var tween := create_tween()
	tween.tween_property(flash_rect, "color", Color(0, 0, 0, 0.9), 0.25)
	tween.tween_interval(0.6)
	tween.tween_property(flash_rect, "color", Color(0, 0, 0, 0.0), 1.0)
	prompt_label.visible = true


func _on_money_changed(amount: int, delta: int) -> void:
	if money_label == null:
		return
	money_label.text = GameData.price_string(amount)
	if delta != 0:
		var color := UIKit.ACCENT if delta > 0 else UIKit.BAD
		money_label.add_theme_color_override("font_color", color)
		var tween := create_tween()
		tween.tween_interval(0.9)
		tween.tween_callback(func(): money_label.add_theme_color_override("font_color", UIKit.ACCENT))


func _on_counts_changed(served: int, total: int) -> void:
	if served_label:
		served_label.text = "SERVED %d/%d" % [served, total]


func _on_checkout_ready() -> void:
	AudioManager.ui("ui_select")


func _on_scan_progress(scanned: int, total: int) -> void:
	if checkout_label and checkout != null:
		checkout_label.text = "ITEMS %d/%d   %s" % [scanned, total, GameData.price_string(checkout.total_cents)]


func set_shift_title(text: String) -> void:
	if shift_label:
		shift_label.text = text

