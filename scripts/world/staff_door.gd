extends StaticBody3D
## Swinging staff-room door. Also used by the horror director to open on its own.

var open_angle := deg_to_rad(94.0)
var is_open := false
var busy := false


func interact(_player: Node = null) -> void:
	toggle()


func toggle() -> void:
	if busy:
		return
	busy = true
	is_open = not is_open
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation:y", open_angle if is_open else 0.0, 0.75)
	tween.tween_callback(_clear_busy)
	AudioManager.play_at("door_slam", global_position + Vector3(0, 1.0, 0), -22.0, 1.45 if is_open else 1.1)


func open_slowly(duration: float = 3.0) -> void:
	if is_open or busy:
		return
	busy = true
	is_open = true
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(self, "rotation:y", open_angle, duration)
	tween.tween_callback(_clear_busy)
	AudioManager.play_at("door_slam", global_position + Vector3(0, 1.0, 0), -27.0, 0.65)


func _clear_busy() -> void:
	busy = false


func _get_configuration_warnings() -> PackedStringArray:
	return PackedStringArray()
