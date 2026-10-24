extends Node
## Procedural audio: buses, one-shot pool, positional pool and ambience beds.
##
## The whole library is synthesised in _ready(); nothing is loaded from disk,
## so APK size stays small and every sound can be tuned in one place.

const BUSES := ["SFX", "Ambience", "Voice", "Music"]

var _streams: Dictionary = {}
var _pool_2d: Array[AudioStreamPlayer] = []
var _pool_3d: Array[AudioStreamPlayer3D] = []
var _ambience: Dictionary = {}
var _next_2d := 0
var _next_3d := 0

var tension := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_buses()
	_build_library()
	_build_pools()
	SettingsManager.apply_audio()


func _setup_buses() -> void:
	for bus_name in BUSES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")


func _build_pools() -> void:
	for i in 12:
		var player := AudioStreamPlayer.new()
		player.bus = "SFX"
		add_child(player)
		_pool_2d.append(player)
	for i in 10:
		var player_3d := AudioStreamPlayer3D.new()
		player_3d.bus = "SFX"
		player_3d.max_distance = 24.0
		player_3d.unit_size = 6.0
		player_3d.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		add_child(player_3d)
		_pool_3d.append(player_3d)


func _build_library() -> void:
	var S := AudioSynth

	# Scanner / register
	_streams["scan"] = S.to_wav(S.apply_envelope(
		S.mix(S.sine(1240.0, 0.10, 0.55), S.sine(1860.0, 0.10, 0.25)), 0.003, 0.07))
	_streams["scan_fail"] = S.to_wav(S.mix(
		S.apply_envelope(S.square(180.0, 0.16, 0.22), 0.01, 0.1),
		S.apply_envelope(S.square(120.0, 0.16, 0.18), 0.01, 0.1)))
	_streams["scan_ok"] = S.to_wav(S.apply_envelope(
		S.concat(S.sine(1568.0, 0.06, 0.4), S.sine(2093.0, 0.09, 0.4)), 0.003, 0.06))
	_streams["receipt"] = _make_receipt()
	_streams["register_open"] = S.to_wav(S.apply_envelope(
		S.mix(S.sine(784.0, 0.35, 0.3), S.sine(1176.0, 0.35, 0.18)), 0.01, 0.3))
	_streams["cash"] = _make_cash()

	# UI
	_streams["ui_move"] = S.to_wav(S.apply_envelope(S.sine(520.0, 0.05, 0.18), 0.002, 0.04))
	_streams["ui_select"] = S.to_wav(S.apply_envelope(
		S.mix(S.sine(660.0, 0.09, 0.28), S.sine(990.0, 0.09, 0.12)), 0.002, 0.07))
	_streams["ui_back"] = S.to_wav(S.apply_envelope(S.sweep(420.0, 300.0, 0.09, 0.22), 0.002, 0.06))
	_streams["ui_deny"] = S.to_wav(S.apply_envelope(S.square(140.0, 0.12, 0.16), 0.004, 0.08))

	# World
	_streams["door_chime"] = _make_door_chime()
	_streams["door_slam"] = S.to_wav(S.apply_envelope(S.mix(
		S.noise(0.35, 0.5, 0.86, 12), S.sine(70.0, 0.35, 0.4)), 0.002, 0.3))
	_streams["step_1"] = _make_step(1)
	_streams["step_2"] = _make_step(2)
	_streams["step_3"] = _make_step(3)
	_streams["step_4"] = _make_step(4)
	_streams["cart"] = _make_cart()
	_streams["product_fall"] = _make_product_fall()
	_streams["breaker"] = _make_breaker()
	_streams["bang"] = S.to_wav(S.apply_envelope(S.mix(
		S.noise(0.4, 0.45, 0.9, 33), S.sweep(120.0, 45.0, 0.4, 0.5)), 0.002, 0.35))
	_streams["phone"] = _make_phone()

	# Horror
	_streams["stinger_soft"] = _make_stinger_soft()
	_streams["stinger_hard"] = _make_stinger_hard()
	_streams["scream"] = _make_scream()
	_streams["whisper"] = _make_whisper()
	_streams["breath"] = _make_breath()
	_streams["clue"] = S.to_wav(S.apply_envelope(S.mix(
		S.sine(880.0, 0.25, 0.25), S.sine(1320.0, 0.25, 0.12)), 0.004, 0.2))
	_streams["heartbeat"] = _make_heartbeat()
	_streams["static"] = _make_static()
	_streams["flesh"] = _make_flesh()

	# Ambience beds
	_streams["hum_loop"] = _make_hum()
	_streams["fridge_loop"] = _make_fridge()
	_streams["buzz_loop"] = _make_buzz()
	_streams["room_loop"] = _make_room_tone()
	_streams["exterior_loop"] = _make_exterior()


# --- Generators -------------------------------------------------------------

func _make_step(seed_value: int) -> AudioStreamWAV:
	var S := AudioSynth
	var body := S.lowpass(S.noise(0.09, 0.5, 0.6, seed_value), 900.0)
	body = S.apply_envelope(body, 0.002, 0.06)
	var click := S.apply_envelope(S.sine(150.0 + seed_value * 12.0, 0.05, 0.2), 0.001, 0.04)
	return S.to_wav(S.mix(body, click))


func _make_receipt() -> AudioStreamWAV:
	var S := AudioSynth
	var out := S.silence(0.75)
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in 11:
		var tick := S.apply_envelope(S.noise(0.02, 0.22, 0.3, i + 3), 0.001, 0.012)
		out = S.overlay(out, tick, 0.05 * i + rng.randf() * 0.01)
	out = S.overlay(out, S.apply_envelope(S.sine(90.0, 0.3, 0.12), 0.02, 0.2), 0.05)
	return S.to_wav(out)


func _make_cash() -> AudioStreamWAV:
	var S := AudioSynth
	var out := S.silence(0.8)
	for i in 6:
		var freq := 1500.0 + i * 260.0
		var note := S.apply_envelope(S.mix(S.sine(freq, 0.22, 0.16), S.sine(freq * 1.5, 0.22, 0.06)), 0.002, 0.2)
		out = S.overlay(out, note, i * 0.06)
	return S.to_wav(out)


func _make_door_chime() -> AudioStreamWAV:
	var S := AudioSynth
	var first := S.apply_envelope(S.mix(S.sine(1318.0, 0.5, 0.22), S.sine(2637.0, 0.5, 0.05)), 0.004, 0.45)
	var second := S.apply_envelope(S.mix(S.sine(1046.0, 0.7, 0.22), S.sine(2093.0, 0.7, 0.05)), 0.004, 0.62)
	return S.to_wav(S.concat(first, second))


func _make_cart() -> AudioStreamWAV:
	var S := AudioSynth
	var rumble := S.lowpass(S.noise(1.2, 0.35, 0.9, 77), 420.0)
	var rattle := S.lowpass(S.noise(1.2, 0.18, 0.55, 78), 1800.0)
	var out := S.mix(rumble, rattle)
	var wobble := S.sine(6.5, 1.2, 0.06)
	for i in out.size():
		out[i] = out[i] * (0.85 + wobble[i])
	return S.to_wav(S.apply_envelope(out, 0.15, 0.3))


func _make_product_fall() -> AudioStreamWAV:
	var S := AudioSynth
	var out := S.apply_envelope(S.mix(S.noise(0.18, 0.4, 0.5, 9), S.sine(220.0, 0.18, 0.15)), 0.001, 0.14)
	out = S.concat(out, S.apply_envelope(S.mix(S.noise(0.25, 0.3, 0.7, 10), S.sine(110.0, 0.25, 0.2)), 0.002, 0.2))
	return S.to_wav(out)


func _make_breaker() -> AudioStreamWAV:
	var S := AudioSynth
	var crack := S.apply_envelope(S.noise(0.12, 0.6, 0.35, 21), 0.001, 0.08)
	var hum := S.apply_envelope(S.square(60.0, 0.6, 0.18), 0.05, 0.5)
	return S.to_wav(S.mix(crack, hum))


func _make_phone() -> AudioStreamWAV:
	var S := AudioSynth
	var ring := S.silence(1.0)
	for i in 2:
		var burst := S.apply_envelope(S.mix(S.sine(950.0, 0.35, 0.16), S.sine(1400.0, 0.35, 0.1)), 0.01, 0.05)
		ring = S.overlay(ring, burst, i * 0.45)
	return S.to_wav(ring, true)


func _make_stinger_soft() -> AudioStreamWAV:
	var S := AudioSynth
	var out := S.sweep(220.0, 60.0, 1.6, 0.35)
	out = S.lowpass(out, 1200.0)
	out = S.mix(out, S.apply_envelope(S.noise(1.6, 0.12, 0.97, 5), 0.4, 0.8))
	return S.to_wav(S.apply_envelope(out, 0.3, 1.0))


func _make_stinger_hard() -> AudioStreamWAV:
	var S := AudioSynth
	var sweep := S.sweep(1800.0, 80.0, 1.1, 0.45)
	var noise := S.apply_envelope(S.noise(1.1, 0.4, 0.55, 8), 0.002, 0.9)
	var sub := S.apply_envelope(S.sine(48.0, 1.1, 0.5), 0.01, 0.8)
	return S.to_wav(S.mix(S.mix(sweep, noise), sub))


func _make_scream() -> AudioStreamWAV:
	var S := AudioSynth
	var voice := S.sweep(900.0, 280.0, 1.2, 0.40)
	var growl := S.square(120.0, 1.2, 0.16)
	var out := S.mix(voice, growl)
	var shred := S.apply_envelope(S.noise(1.2, 0.35, 0.2, 41), 0.001, 0.9)
	out = S.mix(out, shred)
	return S.to_wav(S.apply_envelope(out, 0.005, 0.7))


func _make_whisper() -> AudioStreamWAV:
	var S := AudioSynth
	var out := S.silence(2.4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in 7:
		var length := rng.randf_range(0.12, 0.30)
		var burst := S.noise(length, 0.5, 0.35, 200 + i)
		burst = S.lowpass(burst, 2200.0)
		burst = S.apply_envelope(burst, 0.03, length * 0.6)
		out = S.overlay(out, burst, rng.randf_range(0.0, 2.0))
	return S.to_wav(out)


func _make_breath() -> AudioStreamWAV:
	var S := AudioSynth
	var inhale := S.apply_envelope(S.lowpass(S.noise(1.1, 0.4, 0.85, 61), 900.0), 0.6, 0.4)
	var exhale := S.apply_envelope(S.lowpass(S.noise(1.3, 0.5, 0.8, 62), 700.0), 0.3, 0.9)
	return S.to_wav(S.concat(inhale, exhale))


func _make_heartbeat() -> AudioStreamWAV:
	var S := AudioSynth
	var out := S.silence(1.2)
	out = S.overlay(out, S.apply_envelope(S.sine(56.0, 0.16, 0.5), 0.005, 0.13), 0.0)
	out = S.overlay(out, S.apply_envelope(S.sine(48.0, 0.20, 0.35), 0.005, 0.17), 0.28)
	return S.to_wav(out, true)


func _make_static() -> AudioStreamWAV:
	var S := AudioSynth
	var noise := S.lowpass(S.noise(1.5, 0.3, 0.15, 111), 5200.0)
	return S.to_wav(S.apply_envelope(noise, 0.02, 0.05), true)


func _make_flesh() -> AudioStreamWAV:
	var S := AudioSynth
	var wet := S.lowpass(S.noise(0.35, 0.5, 0.25, 71), 700.0)
	var tone := S.sweep(160.0, 55.0, 0.35, 0.3)
	return S.to_wav(S.mix(wet, tone))


# --- Ambience beds ----------------------------------------------------------

## Crossfades the tail into the head so noise loops have no audible seam.
func _loopify(buffer: PackedFloat32Array, fade_seconds: float) -> PackedFloat32Array:
	var fade := int(fade_seconds * AudioSynth.RATE)
	if fade <= 0 or buffer.size() <= fade * 2:
		return buffer
	var out := buffer.duplicate()
	for i in fade:
		var t := float(i) / float(fade)
		out[i] = lerpf(buffer[buffer.size() - fade + i], buffer[i], t)
	out.resize(buffer.size() - fade)
	return out


func _make_hum() -> AudioStreamWAV:
	var S := AudioSynth
	var duration := 4.0
	var out := S.silence(duration)
	out = S.mix(out, S.sine(60.0, duration, 0.10))
	out = S.mix(out, S.sine(120.0, duration, 0.045))
	out = S.mix(out, S.sine(240.0, duration, 0.018))
	var wobble := S.sine(0.25, duration, 1.0)
	for i in out.size():
		out[i] = out[i] * (1.0 + wobble[i] * 0.08)
	return S.to_wav(out, true)


func _make_fridge() -> AudioStreamWAV:
	var S := AudioSynth
	var duration := 3.0
	var out := S.silence(duration)
	out = S.mix(out, S.sine(50.0, duration, 0.09))
	out = S.mix(out, S.sine(100.0, duration, 0.04))
	var air := S.lowpass(S.noise(duration, 0.25, 0.93, 55), 500.0)
	out = S.mix(out, air)
	return S.to_wav(_loopify(out, 0.25), true)


func _make_buzz() -> AudioStreamWAV:
	var S := AudioSynth
	var duration := 2.0
	var out := S.square(120.0, duration, 0.055)
	out = S.mix(out, S.square(240.0, duration, 0.02))
	var flicker := S.sine(2.0, duration, 1.0)
	for i in out.size():
		out[i] = out[i] * (0.85 + flicker[i] * 0.15)
	return S.to_wav(S.lowpass(out, 4000.0), true)


func _make_room_tone() -> AudioStreamWAV:
	var S := AudioSynth
	var duration := 5.0
	var out := S.lowpass(S.noise(duration, 0.16, 0.95, 7), 700.0)
	var swell := S.sine(0.2, duration, 1.0)
	for i in out.size():
		out[i] = out[i] * (0.7 + swell[i] * 0.3)
	return S.to_wav(_loopify(out, 0.5), true)


func _make_exterior() -> AudioStreamWAV:
	var S := AudioSynth
	var duration := 6.0
	var wind := S.lowpass(S.noise(duration, 0.4, 0.96, 13), 420.0)
	var gust := S.sine(0.166, duration, 1.0)
	for i in wind.size():
		wind[i] = wind[i] * (0.55 + gust[i] * 0.45)
	return S.to_wav(_loopify(wind, 0.7), true)


# --- Playback ---------------------------------------------------------------

func has_sound(name: String) -> bool:
	return _streams.has(name)


func play(name: String, volume_db: float = 0.0, pitch: float = 1.0, bus: String = "SFX") -> void:
	var stream: AudioStream = _streams.get(name, null)
	if stream == null:
		push_warning("AudioManager: unknown sound '%s'" % name)
		return
	var player := _pool_2d[_next_2d]
	_next_2d = (_next_2d + 1) % _pool_2d.size()
	player.bus = bus
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch, 0.05)
	player.play()


func play_at(name: String, position: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream: AudioStream = _streams.get(name, null)
	if stream == null:
		return
	var player := _pool_3d[_next_3d]
	_next_3d = (_next_3d + 1) % _pool_3d.size()
	player.stream = stream
	player.global_position = position
	player.volume_db = volume_db
	player.pitch_scale = maxf(pitch, 0.05)
	player.play()


func ui(name: String) -> void:
	play(name, -6.0)


func footstep(position: Vector3, volume_db: float = -10.0) -> void:
	var index := randi_range(1, 4)
	play_at("step_%d" % index, position, volume_db, randf_range(0.92, 1.08))


func voice_blip(pitch: float, volume_db: float = -16.0) -> void:
	if not _streams.has("voice_blip"):
		var S := AudioSynth
		_streams["voice_blip"] = S.to_wav(S.apply_envelope(
			S.mix(S.sine(300.0, 0.045, 0.4), S.sine(600.0, 0.045, 0.15)), 0.003, 0.03))
	play("voice_blip", volume_db, clampf(pitch, 0.5, 2.0), "Voice")


# --- Ambient loops ----------------------------------------------------------

func loop_start(name: String, volume_db: float = -20.0, bus: String = "Ambience", fade: float = 1.5) -> void:
	if _ambience.has(name):
		loop_set_volume(name, volume_db, fade)
		return
	var stream: AudioStream = _streams.get(name, null)
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.bus = bus
	player.stream = stream
	player.volume_db = -60.0
	add_child(player)
	player.play()
	_ambience[name] = player
	loop_set_volume(name, volume_db, fade)


func loop_set_volume(name: String, volume_db: float, fade: float = 0.8) -> void:
	if not _ambience.has(name):
		return
	var player: AudioStreamPlayer = _ambience[name]
	var tween := create_tween()
	tween.tween_property(player, "volume_db", volume_db, maxf(fade, 0.01))


func loop_stop(name: String, fade: float = 1.2) -> void:
	if not _ambience.has(name):
		return
	var player: AudioStreamPlayer = _ambience[name]
	_ambience.erase(name)
	var tween := create_tween()
	tween.tween_property(player, "volume_db", -60.0, maxf(fade, 0.01))
	tween.tween_callback(player.queue_free)


func stop_all_ambience(fade: float = 1.0) -> void:
	for name in _ambience.keys():
		loop_stop(name, fade)


## 0 = normal store, 4 = the store is not right tonight.
func set_tension(level: int) -> void:
	tension = clampi(level, 0, 4)
	loop_start("hum_loop", -24.0 + tension * 1.2, "Ambience", 2.0)
	loop_start("room_loop", -22.0, "Ambience", 2.0)
	if tension >= 1:
		loop_start("fridge_loop", -30.0 + tension * 2.0, "Ambience", 2.5)
	else:
		loop_set_volume("fridge_loop", -34.0, 2.0)
	if tension >= 2:
		loop_start("buzz_loop", -36.0 + tension * 2.5, "Ambience", 2.0)
	else:
		loop_stop("buzz_loop", 1.5)


func stinger(hard: bool = false) -> void:
	var amount: float = SettingsManager.stinger_scale()
	play("stinger_hard" if hard else "stinger_soft", linear_to_db(amount), 1.0)
