extends Node
## Input-lock edge cases: every scenario someone could use to strand the player
## without controls. Each case must end with the player controllable again.
##
##   godot --headless --path . -- --night=1 --inputtest

const CUSTOMER_SCENE := preload("res://scenes/customer/customer.tscn")

var _failures := 0
var _checks := 0
var _store: Node
var _player: PlayerController
var _shift: Node
var _inspection: Node
var _hud: Node
var _notebook: Node
var _pause: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_run")


func _check(label: String, condition: bool, detail: String = "") -> void:
	_checks += 1
	if condition:
		print("[OK]   %s   %s" % [label, detail])
	else:
		_failures += 1
		print("[FAIL] %s   %s" % [label, detail])


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _run() -> void:
	for i in 400:
		await get_tree().process_frame
		if get_tree().current_scene != null and get_tree().current_scene.name == "Store":
			_store = get_tree().current_scene
			break
	if _store == null:
		print("[INPUTTEST] store never loaded")
		get_tree().quit(1)
		return

	_player = _store.get_node("Player")
	_shift = _store.get_node("ShiftManager")
	_inspection = _store.get_node("Inspection")
	_hud = _store.get_node("HUD")
	_notebook = _store.get_node("Notebook")
	_pause = _store.get_node("PauseMenu")
	await _wait(0.5)

	var customer := _spawn_customer()

	_check("starts controllable", _player.is_controllable())

	# 1. Dialogue opened twice (double tap), closed once.
	_hud._open_dialogue(customer)
	_hud._open_dialogue(customer)
	await _wait(0.2)
	_check("dialogue locks input", not _player.is_controllable())
	_hud.close_dialogue()
	await _wait(0.8)
	_check("double-opened dialogue releases", _player.is_controllable(), str(GameManager.active_locks()))

	# 2. Inspection begun twice, ended once.
	_inspection.begin(customer)
	_inspection.begin(customer)
	await _wait(0.3)
	_check("inspection locks input", not _player.is_controllable())
	_inspection.end()
	await _wait(0.8)
	_check("inspection releases", _player.is_controllable(), str(GameManager.active_locks()))

	# 3. Inspection abandoned mid-way (broken sequence, never calls end()).
	_inspection.begin(customer)
	await _wait(0.3)
	_inspection.active = false
	_inspection.customer = null
	await _wait(1.0)
	_check("abandoned inspection self-releases", _player.is_controllable(), str(GameManager.active_locks()))
	_inspection.end()

	# 4. A single missed refresh must not strand the player.
	GameManager.hold_input("jumpscare")
	_player.focus_mode(true, 0.6)
	await _wait(1.2)
	_check("leaked jumpscare lock expires", not GameManager.is_modal_open(), str(GameManager.active_locks()))
	_check("leaked jumpscare focus expires", _player.is_controllable())

	# 4b. A scare that is still "active" when the shift ends is aborted.
	var horror = _store.get_node("HorrorDirector")
	horror._scare_active = true
	horror._scare_deadline = Time.get_ticks_msec() + 30000
	GameManager.hold_input("jumpscare")
	GameManager.shift_active = false
	await _wait(0.5)
	_check("scare aborted on shift end", not horror._scare_active and not GameManager.is_modal_open(),
		str(GameManager.active_locks()))
	GameManager.shift_active = true

	# 5. Pause left on with no pause surface (simulate a lost menu).
	GameManager.set_paused(true)
	await _wait(0.15)
	_pause.visible = false
	_pause._open = false
	await _wait(0.6)
	_check("stuck pause is cleared by watchdog", not get_tree().paused)

	# 6. Notebook open, then pause over the top, pause closed, notebook closed.
	_notebook.open()
	await _wait(0.2)
	_pause.toggle()
	await _wait(0.2)
	_pause.toggle()
	await _wait(0.2)
	_check("notebook still locks under paused menu", not _player.is_controllable())
	_notebook.close()
	await _wait(0.8)
	_check("notebook releases after pause", _player.is_controllable(), str(GameManager.active_locks()))

	# 7. Customer disappears while being inspected.
	_inspection.begin(customer)
	await _wait(0.2)
	customer.queue_free()
	await _wait(1.0)
	_check("freed customer ends inspection", not _inspection.active)
	_check("freed customer returns control", _player.is_controllable(), str(GameManager.active_locks()))

	# 8. Shift teardown clears everything.
	GameManager.hold_input("inspection")
	GameManager.finish_shift(false, "input test")
	await _wait(0.2)
	_check("shift end clears locks", not GameManager.is_modal_open(), str(GameManager.active_locks()))

	print("----- INPUT TEST: %d checks, %d failures -----" % [_checks, _failures])
	get_tree().quit(0 if _failures == 0 else 1)


func _spawn_customer() -> Customer:
	var customer := CUSTOMER_SCENE.instantiate() as Customer
	_store.add_child(customer)
	customer.nav_graph = _store.get_node("StoreBuilder").nav_graph
	customer.configure(4242, _shift.shift_data, _shift.rng, false, true)
	customer.global_position = StoreLayout.SERVICE_SPOT
	customer.set_state(Customer.State.AT_COUNTER)
	return customer
