class_name AudioSynth
extends RefCounted
## Tiny offline synthesiser. Every sound in the game is generated from maths
## at startup, which keeps the APK small and gives full control over the
## "wrong" sounds horror needs.

const RATE := 22050


static func silence(duration: float) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	return buffer


static func sine(freq: float, duration: float, amp: float = 1.0, phase: float = 0.0) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	var step := TAU * freq / RATE
	for i in count:
		buffer[i] = sin(phase + step * i) * amp
	return buffer


static func square(freq: float, duration: float, amp: float = 1.0) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	var step := freq / RATE
	for i in count:
		buffer[i] = (1.0 if fmod(i * step, 1.0) < 0.5 else -1.0) * amp
	return buffer


static func saw(freq: float, duration: float, amp: float = 1.0) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	var step := freq / RATE
	for i in count:
		buffer[i] = (fmod(i * step, 1.0) * 2.0 - 1.0) * amp
	return buffer


static func noise(duration: float, amp: float = 1.0, smoothing: float = 0.0, seed_value: int = 1) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var last := 0.0
	for i in count:
		var value := rng.randf_range(-1.0, 1.0)
		if smoothing > 0.0:
			last = lerpf(last, value, 1.0 - smoothing)
			value = last
		buffer[i] = value * amp
	return buffer


## Frequency glide. curve > 1 spends longer near the start frequency.
static func sweep(start_freq: float, end_freq: float, duration: float, amp: float = 1.0) -> PackedFloat32Array:
	var count := int(duration * RATE)
	var buffer := PackedFloat32Array()
	buffer.resize(count)
	var phase := 0.0
	for i in count:
		var t := float(i) / float(maxi(count - 1, 1))
		var freq := lerpf(start_freq, end_freq, t * t)
		phase += TAU * freq / RATE
		buffer[i] = sin(phase) * amp
	return buffer


static func apply_envelope(buffer: PackedFloat32Array, attack: float, release: float, curve: float = 2.0) -> PackedFloat32Array:
	var count := buffer.size()
	if count == 0:
		return buffer
	var attack_samples := maxi(int(attack * RATE), 1)
	var release_samples := maxi(int(release * RATE), 1)
	for i in count:
		var gain := 1.0
		if i < attack_samples:
			gain = float(i) / float(attack_samples)
		var from_end := count - 1 - i
		if from_end < release_samples:
			gain = minf(gain, pow(float(from_end) / float(release_samples), curve))
		buffer[i] = buffer[i] * gain
	return buffer


static func gain(buffer: PackedFloat32Array, amount: float) -> PackedFloat32Array:
	for i in buffer.size():
		buffer[i] = buffer[i] * amount
	return buffer


static func mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var count := maxi(a.size(), b.size())
	var out := PackedFloat32Array()
	out.resize(count)
	for i in count:
		var value := 0.0
		if i < a.size():
			value += a[i]
		if i < b.size():
			value += b[i]
		out[i] = clampf(value, -1.0, 1.0)
	return out


static func overlay(target: PackedFloat32Array, source: PackedFloat32Array, offset_seconds: float) -> PackedFloat32Array:
	var offset := int(offset_seconds * RATE)
	var needed := offset + source.size()
	if needed > target.size():
		target.resize(needed)
	for i in source.size():
		var idx := offset + i
		target[idx] = clampf(target[idx] + source[i], -1.0, 1.0)
	return target


static func concat(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(a.size() + b.size())
	for i in a.size():
		out[i] = a[i]
	for i in b.size():
		out[a.size() + i] = b[i]
	return out


static func lowpass(buffer: PackedFloat32Array, cutoff_hz: float) -> PackedFloat32Array:
	var alpha := clampf(TAU * cutoff_hz / RATE, 0.0, 1.0)
	var previous := 0.0
	for i in buffer.size():
		previous += alpha * (buffer[i] - previous)
		buffer[i] = previous
	return buffer


static func to_wav(buffer: PackedFloat32Array, loop: bool = false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(buffer.size() * 2)
	for i in buffer.size():
		var sample := int(clampf(buffer[i], -1.0, 1.0) * 32000.0)
		bytes.encode_s16(i * 2, sample)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = maxi(buffer.size() - 1, 1)
	return wav
