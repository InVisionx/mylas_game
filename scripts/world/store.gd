extends Node3D
## Store scene root. Builds the world, wires every system together, then starts
## the shift. All actual behaviour lives in the systems it points at.

@onready var builder: StoreBuilder = $StoreBuilder
@onready var player: PlayerController = $Player
@onready var checkout: CheckoutManager = $Checkout
@onready var shift: ShiftManager = $ShiftManager
@onready var inspection: InspectionManager = $Inspection
@onready var horror: HorrorDirector = $HorrorDirector
@onready var security: SecurityMonitor = $SecurityMonitor
@onready var hud: GameHUD = $HUD
@onready var pause_menu: PauseMenu = $PauseMenu
@onready var notebook: NotebookUI = $Notebook
@onready var report: ShiftReport = $ShiftReport


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED if not _is_touch() else Input.MOUSE_MODE_VISIBLE)
	player.global_position = StoreLayout.PLAYER_START
	player.rotation.y = 0.0

	var refs := {
		"builder": builder,
		"player": player,
		"checkout": checkout,
		"shift": shift,
		"inspection": inspection,
		"horror": horror,
		"security": security,
		"hud": hud,
		"notebook": notebook,
	}
	checkout.setup(builder)
	inspection.setup(player)
	security.setup(refs)
	horror.setup(refs)
	shift.setup(refs)
	hud.setup(refs)
	SettingsManager.apply_graphics()
	AudioManager.loop_start("exterior_loop", -36.0, "Ambience", 3.0)
	AudioManager.play("register_open", -14.0)
	call_deferred("_begin_shift")


func _is_touch() -> bool:
	return DisplayServer.is_touchscreen_available() and OS.has_feature("mobile")


func _begin_shift() -> void:
	var data := GameManager.current_shift
	var title := "%s · %s" % [str(data.get("name", "Night")), str(data.get("title", "Shift"))]
	hud.set_shift_title(title.to_upper())
	shift.start_shift()
	_show_briefing(data)


func _show_briefing(data: Dictionary) -> void:
	var lines: Array = data.get("briefing", [])
	for line in lines:
		Events.notify.emit(str(line), "info")
		await get_tree().create_timer(2.6).timeout
		if not is_inside_tree():
			return
	Events.notify.emit("Clock in complete. Serve the book.", "good")
