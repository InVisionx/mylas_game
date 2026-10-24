extends Node
## Always-on flight recorder. Writes a small rolling log to user:// so a crash
## on the handheld can be diagnosed afterwards, and exposes live counters for
## the pause menu.
##
## Log location on Android: /data/data/com.nightowl.nightshift/files/diagnostics.log
## Pull it with: adb shell run-as com.nightowl.nightshift cat files/diagnostics.log

const LOG_PATH := "user://diagnostics.log"
const LOCK_PATH := "user://session_active.lock"
const MAX_BYTES := 512 * 1024
const SAMPLE_SECONDS := 30.0

var previous_session_crashed := false
var session_started_ms := 0

var _file: FileAccess
var _timer: Timer
var _events: PackedStringArray = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	session_started_ms = Time.get_ticks_msec()
	previous_session_crashed = FileAccess.file_exists(LOCK_PATH)
	_open_log()
	if previous_session_crashed:
		_line("PREVIOUS SESSION ENDED WITHOUT A CLEAN SHUTDOWN")
		_events.append("Previous session ended without a clean shutdown")
	var info := Engine.get_version_info()
	_line("=== launch %s ===" % Time.get_datetime_string_from_system())
	_line("build %s (%s)  godot %s  %s/%s" % [
		UpdateManager.current_name, UpdateManager.current_code,
		str(info.get("string", "")), OS.get_name(), OS.get_model_name(),
	])
	_line("screen %s  renderer %s  cpu %d" % [
		str(DisplayServer.window_get_size()), str(RenderingServer.get_video_adapter_name()), OS.get_processor_count(),
	])
	_write_lock()

	_timer = Timer.new()
	_timer.wait_time = SAMPLE_SECONDS
	_timer.autostart = true
	_timer.ignore_time_scale = true
	add_child(_timer)
	_timer.timeout.connect(_sample)


func _open_log() -> void:
	if not FileAccess.file_exists(LOG_PATH):
		var created := FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if created:
			created.close()
	elif FileAccess.get_file_as_bytes(LOG_PATH).size() > MAX_BYTES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOG_PATH))
		var recreated := FileAccess.open(LOG_PATH, FileAccess.WRITE)
		if recreated:
			recreated.close()
	_file = FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if _file:
		_file.seek_end()
	else:
		push_warning("Diagnostics: could not open %s (%s)" % [LOG_PATH, FileAccess.get_open_error()])
	print("[DIAG] log file: %s" % ProjectSettings.globalize_path(LOG_PATH))


func _write_lock() -> void:
	var lock := FileAccess.open(LOCK_PATH, FileAccess.WRITE)
	if lock:
		lock.store_string(str(Time.get_unix_time_from_system()))
		lock.close()


func _line(text: String) -> void:
	if _file == null:
		return
	_file.store_line("[%s] %s" % [Time.get_datetime_string_from_system(), text])
	_file.flush()


## Public hook for gameplay events worth keeping in the record.
func log_event(text: String) -> void:
	_line("EVENT %s" % text)
	_events.append(text)
	if _events.size() > 40:
		_events.remove_at(0)


func _sample() -> void:
	var scene := ""
	if get_tree().current_scene != null:
		scene = str(get_tree().current_scene.name)
	_line("tick up=%ds scene=%s fps=%d obj=%d nodes=%d orphans=%d mem=%.2fMB" % [
		int((Time.get_ticks_msec() - session_started_ms) / 1000),
		scene,
		int(Performance.get_monitor(Performance.TIME_FPS)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		OS.get_static_memory_usage() / 1048576.0,
	])


func live_summary() -> String:
	var lines := PackedStringArray()
	lines.append("uptime        %d s" % int((Time.get_ticks_msec() - session_started_ms) / 1000))
	lines.append("fps           %d" % int(Performance.get_monitor(Performance.TIME_FPS)))
	lines.append("memory        %.1f MB" % (OS.get_static_memory_usage() / 1048576.0))
	lines.append("objects       %d" % int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	lines.append("nodes         %d" % int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)))
	lines.append("orphan nodes  %d" % int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)))
	var customers := get_tree().get_nodes_in_group("customers").size()
	lines.append("customers     %d" % customers)
	return "\n".join(lines)


func tail(count: int = 12) -> String:
	return _tail_file(LOG_PATH, count)


## The engine's own log catches script errors and (on Android) native messages.
func engine_tail(count: int = 20) -> String:
	var path := str(ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log"))
	if not FileAccess.file_exists(path):
		return "(engine log not available)"
	return _tail_file(path, count)


func _tail_file(path: String, count: int) -> String:
	if not FileAccess.file_exists(path):
		return "(no log yet)"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "(log unreadable)"
	var all := file.get_as_text().split("\n", false)
	file.close()
	var start := maxi(0, all.size() - count)
	var out := PackedStringArray()
	for i in range(start, all.size()):
		out.append(str(all[i]))
	return "\n".join(out)


func log_path_display() -> String:
	return LOG_PATH.replace("user://", "")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE:
		_shutdown()


func _shutdown() -> void:
	if _file == null:
		return
	var scene := ""
	if get_tree() != null and get_tree().current_scene != null:
		scene = str(get_tree().current_scene.name)
	_line("=== clean shutdown (scene %s, uptime %ds) ===" % [scene, int((Time.get_ticks_msec() - session_started_ms) / 1000)])
	_file.close()
	_file = null
	if FileAccess.file_exists(LOCK_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LOCK_PATH))
