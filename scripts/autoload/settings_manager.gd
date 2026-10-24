extends Node
## Persistent settings: graphics, audio, horror intensity, controls.
##
## Stored as user://settings.cfg so it survives reinstalls of the game data
## and stays human-readable when debugging on the handheld.

const SETTINGS_PATH := "user://settings.cfg"

const QUALITY_NAMES := ["Low", "Medium", "High"]
const QUALITY_SHADOW_ATLAS := [1024, 2048, 4096]
const QUALITY_RENDER_SCALE := [0.72, 0.85, 1.0]

var graphics := {
	"quality": 1,
	"fps_cap": 60,
	"render_scale": 1.0,
	"shadows": true,
	"fov": 75.0,
}

var audio := {
	"master": 0.9,
	"sfx": 1.0,
	"ambience": 0.8,
	"voice": 1.0,
	"music": 0.6,
}

var horror := {
	"reduced_flash": false,
	"reduced_audio": false,
	"intensity": 1.0,
	"subtitles": true,
}

var controls := {
	"sensitivity": 1.0,
	"sensitivity_y": 1.0,
	"deadzone": 0.18,
	"invert_y": false,
	"invert_x": false,
	"aim_assist": true,
	"vibration": true,
	"fast_checkout": false,
	"toggle_sprint": false,
}

## action -> binding dictionary, only for actions the player has remapped.
var bindings: Dictionary = {}


func _ready() -> void:
	load_settings()
	apply_all()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	for section in ["graphics", "audio", "horror", "controls"]:
		if not cfg.has_section(section):
			continue
		var target: Dictionary = get(section)
		for key in target.keys():
			if cfg.has_section_key(section, key):
				target[key] = cfg.get_value(section, key)
	if cfg.has_section("bindings"):
		for key in cfg.get_section_keys("bindings"):
			bindings[key] = cfg.get_value("bindings", key)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	for section in ["graphics", "audio", "horror", "controls"]:
		var source: Dictionary = get(section)
		for key in source.keys():
			cfg.set_value(section, key, source[key])
	for key in bindings.keys():
		cfg.set_value("bindings", key, bindings[key])
	cfg.save(SETTINGS_PATH)


func apply_all() -> void:
	apply_graphics()
	apply_audio()


func apply_graphics() -> void:
	var quality: int = clampi(int(graphics["quality"]), 0, 2)
	Engine.max_fps = int(graphics["fps_cap"])
	var viewport := get_tree().root
	if viewport:
		viewport.scaling_3d_scale = float(graphics["render_scale"]) * QUALITY_RENDER_SCALE[quality]
		viewport.positional_shadow_atlas_size = QUALITY_SHADOW_ATLAS[quality]
	# Trim optional fill lights on low-end quality settings.
	var index := 0
	for light in get_tree().get_nodes_in_group("ambience_lights"):
		index += 1
		if light is Node3D:
			light.visible = quality > 0 or index <= 2
	Events.graphics_changed.emit()


func apply_audio() -> void:
	_set_bus_volume("Master", audio["master"])
	_set_bus_volume("SFX", audio["sfx"])
	_set_bus_volume("Ambience", audio["ambience"])
	_set_bus_volume("Voice", audio["voice"])
	_set_bus_volume("Music", audio["music"])


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	var value := clampf(float(linear), 0.0, 1.0)
	AudioServer.set_bus_mute(idx, value <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(value, 0.001)))


func set_graphics_value(key: String, value: Variant) -> void:
	graphics[key] = value
	apply_graphics()
	save_settings()
	Events.settings_changed.emit()


func set_audio_value(key: String, value: Variant) -> void:
	audio[key] = value
	apply_audio()
	save_settings()
	Events.settings_changed.emit()


func set_horror_value(key: String, value: Variant) -> void:
	horror[key] = value
	save_settings()
	Events.settings_changed.emit()


func set_control_value(key: String, value: Variant) -> void:
	controls[key] = value
	save_settings()
	Events.settings_changed.emit()


func quality_name() -> String:
	return QUALITY_NAMES[clampi(int(graphics["quality"]), 0, 2)]


## Reduced-intensity horror mode: dimmer flashes, quieter stingers.
func flash_scale() -> float:
	return 0.25 if horror["reduced_flash"] else 1.0


func stinger_scale() -> float:
	return 0.4 if horror["reduced_audio"] else 1.0


func horror_intensity() -> float:
	var value: float = clampf(float(horror["intensity"]), 0.0, 1.0)
	if horror["reduced_flash"]:
		value *= 0.5
	return value
