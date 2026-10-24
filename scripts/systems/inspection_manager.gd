class_name InspectionManager
extends Node
## Zoom-and-study inspection.
##
## One body part at a time, held with the D-pad. Dwell long enough and the
## truth shows itself, so nothing depends on pixel-perfect aiming.

signal inspection_opened(customer: Customer)
signal inspection_closed()

var player: PlayerController
var customer: Customer = null
var active := false
var zoomed := false

var _focus_index := 0
var _dwell := 0.0
var _needed := 1.0
var _resolve_pause := 0.0
var _revealed_focus := {}
var _base_fov := 75.0
var _studied: Array = []
var _last_text := ""

const FOCUS_LABELS := {
	"face": "FACE / EXPRESSION",
	"eyes": "EYES",
	"mouth": "MOUTH / TEETH",
	"hands": "HANDS",
	"neck": "NECK",
	"posture": "POSTURE / BREATHING",
	"reflection": "REFLECTION",
	"shadow": "SHADOW",
	"behavior": "BEHAVIOUR",
	"items": "THEIR ITEMS",
	"payment": "PAYMENT CARD",
	"register": "REGISTER / RECEIPT",
	"camera": "SECURITY FEED",
}


func setup(player_ref: PlayerController) -> void:
	player = player_ref
	add_to_group("inspection_manager")


func begin(target: Customer) -> void:
	if active or target == null or not is_instance_valid(target):
		return
	customer = target
	active = true
	_focus_index = 0
	_dwell = 0.0
	_resolve_pause = 0.0
	_revealed_focus.clear()
	_base_fov = float(SettingsManager.graphics.get("fov", 75.0))
	if player:
		player.focus_mode(true, 1.0)
		player.set_fov(46.0)
	_apply_focus()
	GameManager.open_modal("inspection")
	Events.inspection_started.emit(customer.customer_id)
	inspection_opened.emit(customer)


func end() -> void:
	if not active:
		return
	active = false
	_show_text("")
	if player:
		player.focus_mode(false)
		player.set_fov(_base_fov)
	GameManager.close_modal("inspection")
	Events.inspection_ended.emit()
	inspection_closed.emit()
	customer = null


func _process(delta: float) -> void:
	if not active:
		return
	if customer == null or not is_instance_valid(customer):
		# The customer vanished mid-inspection (left, was freed, scene changed).
		end()
		return
	# Keep the lease alive while inspecting; it lapses by itself if we die.
	GameManager.hold_input("inspection")
	if player:
		player.focus_mode(true, 0.6)

	if InputManager.is_just_pressed("cancel") or InputManager.is_just_pressed("inspect"):
		end()
		return

	if _handle_focus_input():
		return

	if InputManager.is_just_pressed("zoom"):
		zoomed = not zoomed
		if player:
			player.set_fov(30.0 if zoomed else 46.0)

	if _resolve_pause > 0.0:
		_resolve_pause -= delta
		if _resolve_pause <= 0.0:
			_dwell = 0.0
			Events.inspection_progress.emit(0.0)
		return

	if player and player.camera and customer:
		player.force_look_at(customer.focus_anchor(current_focus()), 0.2)

	_dwell += delta
	var ratio := clampf(_dwell / maxf(_needed, 0.05), 0.0, 1.0)
	Events.inspection_progress.emit(ratio)
	if ratio >= 1.0:
		_resolve_focus()


func _handle_focus_input() -> bool:
	if InputManager.is_just_pressed("focus_next") or InputManager.is_just_pressed("focus_prev"):
		var direction := 1 if InputManager.is_just_pressed("focus_next") else -1
		_focus_index = wrapi(_focus_index + direction, 0, StoreLayout.FOCUS_ORDER.size())
		_dwell = 0.0
		_resolve_pause = 0.0
		Events.inspection_progress.emit(0.0)
		_apply_focus()
		AudioManager.ui("ui_move")
		return true
	if InputManager.is_just_pressed("focus_down") or InputManager.is_just_pressed("focus_up"):
		var direction := 1 if InputManager.is_just_pressed("focus_down") else -1
		_focus_index = wrapi(_focus_index + direction, 0, StoreLayout.FOCUS_ORDER.size())
		_dwell = 0.0
		_resolve_pause = 0.0
		Events.inspection_progress.emit(0.0)
		_apply_focus()
		AudioManager.ui("ui_move")
		return true
	return false


func current_focus() -> String:
	return StoreLayout.FOCUS_ORDER[_focus_index]


func _apply_focus() -> void:
	var focus := current_focus()
	_needed = _dwell_needed(focus)
	Events.inspection_focus_changed.emit(focus, str(FOCUS_LABELS.get(focus, focus.to_upper())))
	if player and customer:
		player.force_look_at(customer.focus_anchor(focus), 0.3)
	_show_text(_stage_hint(focus))


func _dwell_needed(focus: String) -> float:
	if customer == null:
		return 1.0
	var anomalies := customer.anomalies_with_focus(focus)
	var needed := 1.0
	for anomaly in anomalies:
		needed = maxf(needed, float(anomaly.get("time", 1.0)))
	if focus == "behavior":
		needed = maxf(needed, 2.4)
	elif focus in ["items", "payment", "register"]:
		needed = maxf(needed, 1.2)
	elif focus == "camera":
		needed = maxf(needed, 1.4)
	return needed


func _stage_hint(focus: String) -> String:
	if focus in ["items", "payment", "register"] and not _at_counter():
		return "Bring them to the counter to check that."
	if focus == "behavior":
		return "Wait. Do not fill the silence."
	if focus == "reflection":
		return "The glass behind them. Look past the body."
	if focus == "shadow":
		return "Down at the floor. Compare it to their feet."
	if focus == "camera":
		return "The monitor by the register shows this aisle."
	if focus == "eyes":
		return "Eyes. Blinking, alignment, where they point."
	if focus == "hands":
		return "Hands. Count what is there."
	return "Study them. Do not rush it."


func _at_counter() -> bool:
	return customer != null and customer.state == Customer.State.AT_COUNTER


func _resolve_focus() -> void:
	if customer == null or not is_instance_valid(customer):
		return
	var focus := current_focus()
	_revealed_focus[focus] = true
	_dwell = 0.0
	Events.inspection_progress.emit(0.0)
	_resolve_pause = 0.9

	if focus in ["items", "payment", "register"] and not _at_counter():
		_show_text("They have nothing on the belt yet.")
		return

	var anomalies := customer.anomalies_with_focus(focus)
	for anomaly in anomalies:
		if customer.reveal_clue(anomaly):
			_show_text(str(anomaly.get("description", "")), true)
			AudioManager.play("clue", -8.0)
			return
		_show_text("You already wrote this down.")
		return

	# Innocent explanation: some people are simply unusual.
	if customer.harmless_trait_focus() == focus and not customer.harmless_trait.is_empty():
		var text := str(customer.harmless_trait.get("text", ""))
		_show_text("%s  (ordinary)" % text)
		AudioManager.play("ui_back", -18.0)
		if not _studied.has(focus):
			_studied.append(focus)
		return

	_show_text(_nothing_text(focus))
	if not _studied.has(focus):
		_studied.append(focus)


func _nothing_text(focus: String) -> String:
	match focus:
		"hands":
			return "Ten fingers. Ordinary knuckles. Nothing to write down."
		"eyes":
			return "They blink. Both eyes agree with each other."
		"mouth":
			return "Normal teeth. An ordinary mouth."
		"neck":
			return "The neck bends exactly as far as a neck bends."
		"posture":
			return "They are breathing. Shoulders move. All normal."
		"face":
			return "An ordinary face, doing ordinary things."
		"reflection":
			return "The glass shows them standing there. It matches."
		"shadow":
			return "The shadow arrives when they do."
		"behavior":
			return "Nothing repeats. Nothing freezes. They wait like a person."
		"items":
			return "Normal groceries. Dates and barcodes are all plausible."
		"payment":
			return "An ordinary card in an ordinary hand."
		"register":
			return "The register behaves. Prices, totals, nothing strange."
		"camera":
			return "On the monitor they look like a person in an aisle."
		_:
			return "Nothing unusual."


func _show_text(text: String, clue: bool = false) -> void:
	if not text.is_empty():
		_last_text = text
	Events.dialogue_line.emit("INSPECTION", text)
	Events.inspection_focus_changed.emit(current_focus(), str(FOCUS_LABELS.get(current_focus(), "")))
	if clue:
		Events.notify.emit("CLUE LOGGED", "clue")


func study_progress() -> float:
	return clampf(_dwell / maxf(_needed, 0.05), 0.0, 1.0)


func studies_done() -> Array:
	return _studied
