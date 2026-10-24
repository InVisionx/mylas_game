class_name SecurityMonitor
extends Node3D
## Low-cost CCTV: one low-res SubViewport that only renders while the player
## is actually looking at the monitor, and only at ~8 fps.

var builder: StoreBuilder
var player: PlayerController

var viewport: SubViewport
var camera: Camera3D
var feed_index := 0
var _update_timer := 0.0
var _screen_mesh: MeshInstance3D
var _material: StandardMaterial3D
var _last_text := ""


func setup(refs: Dictionary) -> void:
	builder = refs.get("builder")
	player = refs.get("player")
	add_to_group("security_monitor")


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.name = "FeedViewport"
	viewport.size = Vector2i(384, 216)
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.transparent_bg = false
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	add_child(viewport)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.near = 0.1
	camera.far = 40.0
	camera.cull_mask = 1 | 4
	viewport.add_child(camera)
	viewport.world_3d = get_world_3d()
	_attach_screen()
	_apply_feed()


func _attach_screen() -> void:
	if builder == null or builder.security_monitor == null:
		return
	_screen_mesh = builder.security_monitor.get_node_or_null("Screen") as MeshInstance3D
	if _screen_mesh == null:
		return
	_material = StandardMaterial3D.new()
	_material.albedo_texture = viewport.get_texture()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_screen_mesh.material_override = _material

	# So the player can walk up and use the monitor.
	var body := StaticBody3D.new()
	body.name = "MonitorHitbox"
	body.collision_layer = 8
	body.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.6, 0.4)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, 1.5, 0.05)
	body.add_child(collision)
	builder.security_monitor.add_child(body)


func _apply_feed() -> void:
	var feeds := StoreLayout.CAMERA_FEEDS
	if feeds.is_empty():
		return
	var feed: Dictionary = feeds[feed_index % feeds.size()]
	camera.global_position = feed["pos"]
	camera.look_at(feed["look"], Vector3.UP)
	_last_text = str(feed.get("label", "CAM"))
	Events.notify.emit(_last_text, "info")
	AudioManager.play("ui_move", -12.0)


func cycle_feed() -> void:
	feed_index = (feed_index + 1) % StoreLayout.CAMERA_FEEDS.size()
	_apply_feed()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func interact(_player_node: Node = null) -> void:
	cycle_feed()


func get_interact_prompt() -> String:
	return "SECURITY FEED — press to change camera"


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return
	if viewport == null:
		return
	_update_timer -= delta
	if _update_timer > 0.0:
		return
	_update_timer = 0.12
	if builder == null or not is_instance_valid(builder) or builder.security_monitor == null:
		return
	if not is_instance_valid(player.camera):
		return
	var to_monitor := (builder.security_monitor.global_position + Vector3(0, 1.5, 0) - player.camera.global_position)
	var distance := to_monitor.length()
	if distance > 6.0:
		return
	var forward := -player.camera.global_transform.basis.z
	if forward.dot(to_monitor.normalized()) < 0.55:
		return
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func feed_label() -> String:
	var feeds := StoreLayout.CAMERA_FEEDS
	if feeds.is_empty():
		return "NO SIGNAL"
	return str(feeds[feed_index % feeds.size()].get("label", "CAM"))
