extends Node
## Launch-time update check against the project's public version manifest.
##
## Android will not let a sideloaded app install an APK silently (that needs
## device-owner/root), so the flow is: detect a newer build on launch, show it
## on the main menu, and one press opens the download in the browser. Tapping
## the downloaded file then installs it over the old build.

signal update_available(info: Dictionary)
signal update_check_finished(has_update: bool)

const MANIFEST_API := "https://api.github.com/repos/InVisionx/mylas_game/contents/dist/version.json?ref=main"
const MANIFEST_RAW := "https://raw.githubusercontent.com/InVisionx/mylas_game/main/dist/version.json"
const FALLBACK_APK := "https://github.com/InVisionx/mylas_game/raw/main/dist/NightShift-NotHuman.apk"

var current_code := 1
var current_name := "0.1.0"

var latest: Dictionary = {}
var has_update := false
var checked := false
var check_failed := false

var _http: HTTPRequest
var _notified := false
var _last_check := 0.0
var _tried_fallback := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current_code = int(ProjectSettings.get_setting("night_shift/version_code", 1))
	current_name = str(ProjectSettings.get_setting("application/config/version", "0.1.0"))


func check_for_update(force: bool = false) -> void:
	if checked and not force:
		return
	checked = true
	check_failed = false
	_tried_fallback = false
	_last_check = Time.get_unix_time_from_system()
	if _http != null and is_instance_valid(_http):
		_http.queue_free()
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	_http.use_threads = true
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	# The contents API is never CDN-cached, so a fresh publish is visible at once.
	# raw.githubusercontent is the fallback (it caches for a few minutes).
	_request(MANIFEST_API, [
		"Accept: application/vnd.github.raw",
		"X-GitHub-Api-Version: 2022-11-28",
		"User-Agent: NightShift-Not-Human",
	])


func _request(url: String, headers: Array) -> void:
	var error := _http.request(url, PackedStringArray(headers))
	if error != OK:
		check_failed = true
		push_warning("UpdateManager: could not start request (%s)" % error)
		update_check_finished.emit(false)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		if not _tried_fallback:
			_tried_fallback = true
			_request(MANIFEST_RAW, [])
			return
		check_failed = true
		update_check_finished.emit(false)
		return
	var text := body.get_string_from_utf8()
	# Tolerate a UTF-8 BOM (PowerShell and some editors add one).
	if text.length() > 0 and text.unicode_at(0) == 0xFEFF:
		text = text.substr(1)
	text = text.strip_edges()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		check_failed = true
		push_warning("UpdateManager: manifest is not valid JSON.")
		update_check_finished.emit(false)
		return
	latest = parsed
	has_update = is_newer(int(parsed.get("code", 0)), current_code)
	if has_update:
		update_available.emit(latest)
	update_check_finished.emit(has_update)


## Kept static so the rule can be unit-tested without a network request.
static func is_newer(remote_code: int, local_code: int) -> bool:
	return remote_code > local_code


func apk_url() -> String:
	var url := str(latest.get("apk_url", ""))
	return url if not url.is_empty() else FALLBACK_APK


func latest_name() -> String:
	return str(latest.get("name", ""))


func release_notes() -> String:
	return str(latest.get("notes", ""))


## Opens the APK download in the device browser (Android downloads then prompts
## to install). Safe to call on desktop too.
func open_update() -> void:
	AudioManager.ui("ui_select")
	OS.shell_open(apk_url())


## Re-check when returning to the menu, but at most once per session unless forced.
func refresh() -> void:
	check_for_update(true)


func refresh_if_stale(seconds: float = 120.0) -> void:
	if Time.get_unix_time_from_system() - _last_check < seconds:
		return
	check_for_update(true)


func version_label() -> String:
	return "v%s  ·  build %d" % [current_name, current_code]


func notification_text() -> String:
	if latest_name().is_empty():
		return "Update available. Open the main menu to download it."
	return "Update %s available. Open the main menu to download it." % latest_name()


func notify_once() -> void:
	if not has_update or _notified:
		return
	_notified = true
	Events.notify.emit(notification_text(), "warn")
