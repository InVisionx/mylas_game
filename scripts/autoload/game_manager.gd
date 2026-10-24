extends Node
## Run-level state: which night is being played, money, meta progression,
## modal UI tracking and scene transitions.
##
## Per-shift orchestration lives in the store's ShiftManager node; this script
## only owns what must survive between scenes.

const MENU_SCENE := "res://scenes/main_menu.tscn"
const STORE_SCENE := "res://scenes/store.tscn"

var profile: Dictionary = {}

var mode := "story"          ## "story" or "endless"
var endless_round := 0
var shift_index := 1
var shift_active := false
var current_shift: Dictionary = {}
var shift_seed := 0

## Totals accumulated during the current shift only.
var session := {}

var modal_count := 0
var last_report: Dictionary = {}

## Input locks are leases, not counters: every holder re-asserts each frame and
## they expire on their own. A crashed, freed or buggy UI can therefore never
## leave the player without controls.
const INPUT_LOCK_LEASE_MS := 500
var _input_locks: Dictionary = {}

var rng := RandomNumberGenerator.new()
var seed_locked := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	profile = SaveManager.load_profile()
	rng.randomize()


func _new_session() -> void:
	session = {
		"served": 0,
		"humans_approved": 0,
		"entities_rejected": 0,
		"humans_rejected": 0,
		"entities_approved": 0,
		"correct": 0,
		"wrong": 0,
		"money": 0,
		"penalty": 0,
		"scans": 0,
		"entities_total": 0,
		"clues": [],
		"jumpscares": 0,
	}


func set_seed(value: int) -> void:
	seed_locked = true
	shift_seed = value
	rng.seed = value
	seed(value)


func new_shift_seed() -> void:
	if seed_locked:
		rng.seed = shift_seed
		return
	shift_seed = randi()
	rng.seed = shift_seed
	seed(shift_seed)


func has_save_progress() -> bool:
	return int(profile.get("shifts_completed", 0)) > 0


func unlocked_shift() -> int:
	return clampi(int(profile.get("unlocked_shift", 1)), 1, GameData.shift_count())


func is_endless_unlocked() -> bool:
	return bool(profile.get("endless_unlocked", false)) or int(profile.get("shifts_completed", 0)) >= GameData.shift_count()


# --- Scene flow -------------------------------------------------------------

func start_story_shift(index: int) -> void:
	mode = "story"
	shift_index = clampi(index, 1, GameData.shift_count())
	begin_shift(GameData.get_shift(shift_index))


func start_endless(round_index: int) -> void:
	mode = "endless"
	endless_round = maxi(round_index, 1)
	shift_index = 100 + endless_round
	begin_shift(GameData.endless_shift(endless_round))


func begin_shift(config: Dictionary) -> void:
	current_shift = config
	_new_session()
	new_shift_seed()
	shift_active = true
	AudioManager.stop_all_ambience(0.4)
	change_scene(STORE_SCENE)


func abort_shift() -> void:
	shift_active = false
	set_paused(false)
	change_scene(MENU_SCENE)


func return_to_menu() -> void:
	shift_active = false
	set_paused(false)
	AudioManager.stop_all_ambience(0.6)
	change_scene(MENU_SCENE)


func change_scene(path: String) -> void:
	InputManager.touch_active = false
	get_tree().paused = false
	Diagnostics.log_event("scene -> %s" % path)
	get_tree().call_deferred("change_scene_to_file", path)


func restart_current_shift() -> void:
	set_paused(false)
	if mode == "endless":
		start_endless(endless_round)
	else:
		start_story_shift(shift_index)


# --- Pause / modal ----------------------------------------------------------

func set_paused(value: bool) -> void:
	get_tree().paused = value
	Events.request_pause.emit(value)


func is_paused() -> bool:
	return get_tree().paused


func open_modal(key: String = "generic") -> void:
	hold_input(key)


func close_modal(key: String = "generic") -> void:
	release_input(key)


func hold_input(key: String) -> void:
	_input_locks[key] = Time.get_ticks_msec() + INPUT_LOCK_LEASE_MS


func release_input(key: String) -> void:
	_input_locks.erase(key)


func clear_input_locks() -> void:
	_input_locks.clear()


func is_modal_open() -> bool:
	var now := Time.get_ticks_msec()
	for key in _input_locks.keys():
		if int(_input_locks[key]) < now:
			_input_locks.erase(key)
	return not _input_locks.is_empty()


func active_locks() -> Array:
	is_modal_open()  # prune
	return _input_locks.keys()


## Watchdog: the tree must never stay paused with no visible pause surface.
func _process(_delta: float) -> void:
	if not get_tree().paused:
		return
	if _pause_surface_visible():
		return
	set_paused(false)


func _pause_surface_visible() -> bool:
	for group in ["pause_menu", "shift_report"]:
		for node in get_tree().get_nodes_in_group(group):
			if node is CanvasLayer and node.visible:
				return true
	return false


# --- Money / scoring --------------------------------------------------------

func add_money(amount: int) -> void:
	session["money"] = int(session.get("money", 0)) + amount
	profile["money"] = int(profile.get("money", 0)) + amount
	Events.money_changed.emit(int(profile.get("money", 0)), amount)


func add_penalty(amount: int) -> void:
	session["penalty"] = int(session.get("penalty", 0)) + amount
	profile["money"] = maxi(0, int(profile.get("money", 0)) - amount)
	Events.money_changed.emit(int(profile.get("money", 0)), -amount)


func add_clue(clue_id: String) -> bool:
	var discovered: Array = profile.get("discovered_anomalies", [])
	if discovered.has(clue_id):
		return false
	discovered.append(clue_id)
	profile["discovered_anomalies"] = discovered
	var clues: Array = session.get("clues", [])
	clues.append(clue_id)
	session["clues"] = clues
	SaveManager.save_profile(profile)
	Events.notebook_updated.emit()
	return true


func knows_clue(clue_id: String) -> bool:
	return (profile.get("discovered_anomalies", []) as Array).has(clue_id)


func discovered_count() -> int:
	return (profile.get("discovered_anomalies", []) as Array).size()


# --- Decisions --------------------------------------------------------------

func record_decision(approved: bool, was_entity: bool, customer_name: String, basket_total: int) -> Dictionary:
	var correct := approved != was_entity
	var delta_money := 0
	var delta_penalty := 0
	var message := ""

	if approved and not was_entity:
		delta_money = int(current_shift.get("pay_per_customer", 25)) + int(basket_total * 0.05)
		session["humans_approved"] = int(session.get("humans_approved", 0)) + 1
		message = "Sale completed. %s leaves with their groceries." % customer_name
	elif approved and was_entity:
		session["entities_approved"] = int(session.get("entities_approved", 0)) + 1
		delta_penalty = int(current_shift.get("wrong_fine", 100))
		message = "You let it pay."
	elif not approved and was_entity:
		delta_money = int(current_shift.get("entity_bonus", 200))
		session["entities_rejected"] = int(session.get("entities_rejected", 0)) + 1
		message = "You refused it. It left without a word."
	else:
		session["humans_rejected"] = int(session.get("humans_rejected", 0)) + 1
		delta_penalty = int(current_shift.get("wrong_fine", 100))
		message = "You refused a real person. They will complain."

	if correct:
		session["correct"] = int(session.get("correct", 0)) + 1
	else:
		session["wrong"] = int(session.get("wrong", 0)) + 1
	session["served"] = int(session.get("served", 0)) + 1

	if delta_money > 0:
		add_money(delta_money)
	if delta_penalty > 0:
		add_penalty(delta_penalty)

	return {
		"correct": correct,
		"money": delta_money,
		"penalty": delta_penalty,
		"message": message,
	}


# --- Shift completion -------------------------------------------------------

func finish_shift(failed: bool, reason: String = "") -> Dictionary:
	shift_active = false
	modal_count = 0
	clear_input_locks()
	set_paused(false)

	var total: int = int(session.get("served", 0))
	var correct: int = int(session.get("correct", 0))
	var wrong: int = int(session.get("wrong", 0))
	var accuracy := 100.0
	if correct + wrong > 0:
		accuracy = 100.0 * float(correct) / float(correct + wrong)

	var report := {
		"mode": mode,
		"shift_index": shift_index,
		"round": endless_round,
		"name": str(current_shift.get("name", "Shift")),
		"title": str(current_shift.get("title", "")),
		"served": total,
		"correct": correct,
		"wrong": wrong,
		"accuracy": accuracy,
		"money": int(session.get("money", 0)),
		"penalty": int(session.get("penalty", 0)),
		"entities_rejected": int(session.get("entities_rejected", 0)),
		"entities_approved": int(session.get("entities_approved", 0)),
		"humans_rejected": int(session.get("humans_rejected", 0)),
		"clues": (session.get("clues", []) as Array).duplicate(),
		"failed": failed,
		"reason": reason,
		"unlocked_next": 0,
	}

	var stats: Dictionary = profile.get("stats", {})
	stats["customers_served"] = int(stats.get("customers_served", 0)) + total
	stats["humans_approved"] = int(stats.get("humans_approved", 0)) + int(session.get("humans_approved", 0))
	stats["entities_rejected"] = int(stats.get("entities_rejected", 0)) + int(session.get("entities_rejected", 0))
	stats["humans_rejected"] = int(stats.get("humans_rejected", 0)) + int(session.get("humans_rejected", 0))
	stats["entities_approved"] = int(stats.get("entities_approved", 0)) + int(session.get("entities_approved", 0))
	stats["scans"] = int(stats.get("scans", 0)) + int(session.get("scans", 0))
	stats["shifts_played"] = int(stats.get("shifts_played", 0)) + 1
	stats["best_accuracy"] = maxf(float(stats.get("best_accuracy", 0.0)), accuracy)
	profile["stats"] = stats

	if not failed and mode == "story":
		profile["shifts_completed"] = maxi(int(profile.get("shifts_completed", 0)), shift_index)
		if shift_index + 1 <= GameData.shift_count():
			profile["unlocked_shift"] = maxi(int(profile.get("unlocked_shift", 1)), shift_index + 1)
			report["unlocked_next"] = shift_index + 1
		else:
			profile["unlocked_shift"] = GameData.shift_count()
			profile["endless_unlocked"] = true
	if mode == "endless" and not failed:
		profile["endless_best"] = maxi(int(profile.get("endless_best", 0)), endless_round)
		profile["endless_unlocked"] = true

	SaveManager.save_profile(profile)
	last_report = report
	Events.shift_ended.emit(report)
	return report


func continue_after_report() -> void:
	if mode == "endless":
		start_endless(endless_round + 1)
	elif bool(last_report.get("failed", false)):
		restart_current_shift()
	else:
		var next_index: int = int(last_report.get("unlocked_next", 0))
		if next_index > 0:
			start_story_shift(next_index)
		else:
			return_to_menu()
