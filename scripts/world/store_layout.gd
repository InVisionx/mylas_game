class_name StoreLayout
extends RefCounted
## Pure data + geometry helpers for the store.
##
## Keeping the floor plan in one file means the builder, the navigation graph
## and the AI all agree about where walls and shelves are.

const HALF_W := 9.0            ## x range is -HALF_W .. +HALF_W
const FRONT_Z := 13.0          ## glass storefront
const BACK_Z := -8.0           ## wall with the staff doorways
const ROOM_Z := -14.0          ## back rooms end here
const CEILING := 3.6
const SPAWN_OUTSIDE := Vector3(0.0, 0.0, 15.5)

## Gondola shelving. z0..z1 is the run, x is the centre line.
const SHELVES := [
	{ "id": "shelf_a", "x": -6.2, "z0": -7.5, "z1": 2.0, "label": "DRY GOODS" },
	{ "id": "shelf_b", "x": -2.6, "z0": -7.5, "z1": 2.0, "label": "CANNED" },
	{ "id": "shelf_c", "x": 1.0, "z0": -7.5, "z1": 2.0, "label": "SNACKS" },
	{ "id": "shelf_d", "x": 4.6, "z0": -7.5, "z1": 2.0, "label": "HOUSEHOLD" },
]
const SHELF_HALF_DEPTH := 0.62

const COUNTER_MIN := Vector2(-1.7, 7.45)
const COUNTER_MAX := Vector2(2.9, 8.35)

const FRIDGE_RECT := Rect2(8.35, -7.0, 0.65, 11.0)
const PRODUCE_RECT := Rect2(-8.6, 5.2, 3.4, 1.9)
const FREEZER_RECT := Rect2(-4.0, -7.9, 8.0, 0.9)

const PLAYER_START := Vector3(0.9, 0.0, 9.55)
const PLAYER_LOOK := Vector3(0.0, 0.0, 0.0)

## Where customers stand to be served, outside of the counter.
const QUEUE_SPOTS := [
	Vector3(0.55, 0.0, 6.25),
	Vector3(-0.75, 0.0, 5.35),
	Vector3(-2.05, 0.0, 4.55),
]

## Where a served customer stands while the transaction resolves, and the
## walking route out of the store (around the left end of the counter).
const SERVICE_SPOT := Vector3(0.55, 0.0, 6.25)
const EXIT_ROUTE := [
	Vector3(-2.9, 0.0, 6.9),
	Vector3(-3.0, 0.0, 10.4),
	Vector3(0.0, 0.0, 11.4),
	Vector3(0.0, 0.0, 14.8),
]

const CAMERA_FEEDS := [
	{ "id": "entrance", "label": "CAM 1 — ENTRANCE", "pos": Vector3(-4.6, 3.3, 11.6), "look": Vector3(0.0, 1.1, 7.0) },
	{ "id": "aisles", "label": "CAM 2 — AISLES", "pos": Vector3(0.0, 3.35, 4.9), "look": Vector3(0.2, 1.0, -6.5) },
	{ "id": "register", "label": "CAM 3 — REGISTER", "pos": Vector3(6.6, 3.1, 9.6), "look": Vector3(0.9, 1.0, 7.0) },
	{ "id": "back", "label": "CAM 4 — BACK", "pos": Vector3(-4.0, 3.3, -8.6), "look": Vector3(2.0, 1.0, 2.0) },
]

## Inspection targets are attached to these anchors on the customer rig.
const FOCUS_ORDER := ["face", "eyes", "mouth", "hands", "neck", "posture", "reflection", "shadow", "items", "payment", "register", "camera", "behavior"]


static func shelf_rect(shelf: Dictionary) -> Rect2:
	var x: float = shelf["x"]
	return Rect2(x - SHELF_HALF_DEPTH, shelf["z0"], SHELF_HALF_DEPTH * 2.0, shelf["z1"] - shelf["z0"])


static func occluders() -> Array:
	var rects: Array = []
	for shelf in SHELVES:
		rects.append(shelf_rect(shelf))
	rects.append(Rect2(COUNTER_MIN, COUNTER_MAX - COUNTER_MIN))
	rects.append(FRIDGE_RECT)
	rects.append(PRODUCE_RECT)
	rects.append(FREEZER_RECT)
	# Solid back wall (the staff doorways are for the player, not for AI paths).
	rects.append(Rect2(-9.0, BACK_Z - 0.25, 18.0, 0.5))
	return rects


## Waypoints for the customer nav graph. Positions are on the floor.
static func waypoints() -> Dictionary:
	var points := {
		"outside": Vector3(0.0, 0.0, 15.0),
		"door": Vector3(0.0, 0.0, 11.0),
		"front_center": Vector3(0.0, 0.0, 9.2),
		"exit_alley": Vector3(-3.0, 0.0, 8.9),
		"queue_back": Vector3(-2.05, 0.0, 4.55),
		"cross_front_left": Vector3(-8.0, 0.0, 4.6),
		"cross_front_right": Vector3(7.4, 0.0, 4.6),
		"produce": Vector3(-6.9, 0.0, 4.9),
		"fridge": Vector3(7.4, 0.0, 0.5),
		"wall_left_a": Vector3(-8.2, 0.0, 1.0),
		"wall_left_b": Vector3(-8.2, 0.0, -3.6),
		"back_left": Vector3(-7.6, 0.0, -6.3),
		"back_right": Vector3(7.6, 0.0, -6.3),
	}
	var aisle_x := [-4.4, -0.8, 2.8, 6.6]
	var aisle_z := [3.4, 0.0, -3.4, -6.4]
	for a in aisle_x.size():
		for i in aisle_z.size():
			points["a%d_%d" % [a, i]] = Vector3(aisle_x[a], 0.0, aisle_z[i])
	return points


## True when the straight line a->b crosses any solid fixture.
static func segment_blocked(a: Vector3, b: Vector3) -> bool:
	var from := Vector2(a.x, a.z)
	var to := Vector2(b.x, b.z)
	for rect in occluders():
		if _segment_rect(from, to, rect):
			return true
	return false


static func _segment_rect(from: Vector2, to: Vector2, rect: Rect2) -> bool:
	var expanded := rect.grow(0.28)
	if expanded.has_point(from) or expanded.has_point(to):
		return true
	var steps := int(from.distance_to(to) / 0.35) + 2
	for i in range(1, steps):
		var point := from.lerp(to, float(i) / float(steps))
		if expanded.has_point(point):
			return true
	return false


## Builds an AStar3D over the waypoints, connecting anything with clear line of sight.
static func build_nav_graph(max_link: float = 8.5) -> AStar3D:
	var graph := AStar3D.new()
	var points := waypoints()
	var ids: Array = points.keys()
	var by_id := {}
	var index := 0
	for id in ids:
		var p: Vector3 = points[id]
		graph.add_point(index, p)
		by_id[id] = index
		index += 1

	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Vector3 = points[ids[i]]
			var b: Vector3 = points[ids[j]]
			if a.distance_to(b) > max_link:
				continue
			if segment_blocked(a, b):
				continue
			graph.connect_points(i, j, true)
	return graph


static func waypoint_index(graph: AStar3D, id: String) -> int:
	var points := waypoints()
	if not points.has(id):
		return -1
	var target: Vector3 = points[id]
	for point_id in graph.get_point_ids():
		if graph.get_point_position(point_id).distance_to(target) < 0.05:
			return point_id
	return -1


## What the shift manager calls: a tile-space route between named waypoints.
static func route_between(graph: AStar3D, from_id: String, to_id: String) -> Array:
	var start := waypoint_index(graph, from_id)
	var target := waypoint_index(graph, to_id)
	if start < 0 or target < 0:
		return []
	var points := graph.get_point_path(start, target)
	return Array(points)
