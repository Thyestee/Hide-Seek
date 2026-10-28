extends RefCounted
## Builds the village map from code. Everything is deterministic (fixed layout
## and a fixed random seed) so every peer ends up with the identical map.

const PropLib = preload("res://scripts/world/prop_library.gd")

const GRASS := Color(0.47, 0.70, 0.33)
const DIRT := Color(0.66, 0.53, 0.37)
const COBBLE := Color(0.56, 0.52, 0.47)
const FLOOR := Color(0.56, 0.40, 0.26)
const BEAM := Color(0.36, 0.23, 0.14)
const STONE := Color(0.60, 0.60, 0.62)
const HALF_SIZE := 40.0

var map: Node3D
var hider_spawns: Array[Vector3] = []
var seeker_spawns: Array[Vector3] = []
var _rng := RandomNumberGenerator.new()
var _blocked: Array[Rect2] = []


func build(target: Node3D) -> void:
	map = Node3D.new()
	map.name = "Map"
	target.add_child(map)
	_rng.seed = 20261029
	_ground()
	_boundary()
	_plaza()
	_house(Vector3(-20, 0, -18), 0, 10, 8, 3.2, Color(0.94, 0.88, 0.74), Color(0.72, 0.3, 0.22), _cottage_interior)
	_house(Vector3(0, 0, -25), 0, 12, 8, 3.4, Color(0.86, 0.9, 0.95), Color(0.3, 0.42, 0.68), _hall_interior)
	_house(Vector3(20, 0, -18), 0, 10, 8, 3.2, Color(0.95, 0.85, 0.7), Color(0.35, 0.55, 0.32), _cottage_interior)
	_house(Vector3(-23, 0, 10), 90, 9, 9, 3.2, Color(0.9, 0.82, 0.72), Color(0.6, 0.35, 0.55), _study_interior)
	_house(Vector3(23, 0, 10), -90, 9, 9, 3.2, Color(0.96, 0.92, 0.82), Color(0.75, 0.5, 0.2), _study_interior)
	_house(Vector3(0, 0, 27), 180, 14, 10, 4.6, Color(0.66, 0.24, 0.18), Color(0.32, 0.22, 0.18), _barn_interior, 3.4, 3.4)
	_paths()
	_outdoor()
	_trees()
	_scatter()
	for i in 20:
		var a := i * TAU / 20.0
		hider_spawns.append(Vector3(cos(a) * 6.0, 0.1, sin(a) * 6.0))
	for i in 8:
		var a := i * TAU / 8.0 + 0.2
		seeker_spawns.append(Vector3(cos(a) * 2.4, 0.1, sin(a) * 2.4))


# --- Building blocks ---------------------------------------------------------

func solid(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation = rot
	PropLib.add_box(body, size, Vector3.ZERO, color)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


func solid_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, top_radius := -1.0) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	PropLib.add_cyl(body, radius, height, Vector3.ZERO, color, top_radius)
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, top_radius)
	shape.height = height
	col.shape = shape
	body.add_child(col)
	parent.add_child(body)
	return body


func invisible_wall(size: Vector3, pos: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	map.add_child(body)


func prop(parent: Node3D, id: String, pos: Vector3, yaw_deg := 0.0) -> void:
	var p := PropLib.make_static_prop(id)
	p.position = pos
	p.rotation.y = deg_to_rad(yaw_deg)
	parent.add_child(p)


func props(parent: Node3D, list: Array) -> void:
	for entry in list:
		prop(parent, entry[0], entry[1], entry[2] if entry.size() > 2 else 0.0)


## A wall along from -> to with holes. Each opening is [centre, width, bottom, top]
## measured along the wall from `from`.
func wall(parent: Node3D, from: Vector3, to: Vector3, height: float, color: Color, openings: Array = []) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var yaw := atan2(-dir.z, dir.x)
	var piece := func(a: float, b: float, y0: float, y1: float) -> void:
		if b - a < 0.01 or y1 - y0 < 0.01:
			return
		var centre := from + dir * ((a + b) * 0.5) + Vector3.UP * ((y0 + y1) * 0.5)
		solid(parent, Vector3(b - a, y1 - y0, 0.3), centre, color, Vector3(0, yaw, 0))
	openings.sort_custom(func(x, y): return x[0] < y[0])
	var cursor := 0.0
	for o in openings:
		var start: float = o[0] - o[1] * 0.5
		var end: float = o[0] + o[1] * 0.5
		piece.call(cursor, start, 0.0, height)
		piece.call(start, end, 0.0, o[2])
		piece.call(start, end, o[3], height)
		cursor = end
	piece.call(cursor, length, 0.0, height)


# --- Map sections ------------------------------------------------------------

func _ground() -> void:
	solid(map, Vector3(100, 1, 100), Vector3(0, -0.5, 0), GRASS)
	# Rolling hills outside the fence, purely for the skyline.
	for i in 14:
		var a := i * TAU / 14.0 + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(58.0, 70.0)
		var s := _rng.randf_range(14.0, 24.0)
		PropLib.add_sphere(map, s, Vector3(cos(a) * r, -s * 0.55, sin(a) * r), GRASS.darkened(_rng.randf_range(0.0, 0.15)), Vector3(1.6, 1.0, 1.6))


func _boundary() -> void:
	var edge := HALF_SIZE - 0.5
	for side in 4:
		var horizontal := side < 2
		var side_sign := -1.0 if side % 2 == 0 else 1.0
		var rail_size := Vector3(HALF_SIZE * 2.0, 0.12, 0.08) if horizontal else Vector3(0.08, 0.12, HALF_SIZE * 2.0)
		for y in [0.5, 0.95]:
			var rail_pos := Vector3(0, y, side_sign * edge) if horizontal else Vector3(side_sign * edge, y, 0)
			PropLib.add_box(map, rail_size, rail_pos, PropLib.WOOD)
		var t := -edge
		while t <= edge:
			var post := Vector3(t, 0.6, side_sign * edge) if horizontal else Vector3(side_sign * edge, 0.6, t)
			PropLib.add_box(map, Vector3(0.16, 1.2, 0.16), post, PropLib.WOOD_DARK)
			t += 3.0
		var wall_pos := Vector3(0, 6, side_sign * (HALF_SIZE + 1.0)) if horizontal else Vector3(side_sign * (HALF_SIZE + 1.0), 6, 0)
		var wall_size := Vector3(HALF_SIZE * 2.0 + 4.0, 12, 2) if horizontal else Vector3(2, 12, HALF_SIZE * 2.0 + 4.0)
		invisible_wall(wall_size, wall_pos)


func _plaza() -> void:
	PropLib.add_box(map, Vector3(24, 0.04, 24), Vector3(0, 0.02, 0), COBBLE)
	PropLib.add_box(map, Vector3(24.6, 0.03, 24.6), Vector3(0, 0.015, 0), COBBLE.darkened(0.2))
	# Loose paving stones so the square isn't one flat colour.
	for i in 90:
		var s := _rng.randf_range(0.5, 1.1)
		var shade := COBBLE.darkened(_rng.randf_range(0.05, 0.22)) if i % 3 else COBBLE.lightened(0.08)
		PropLib.add_box(map, Vector3(s, 0.02, s * _rng.randf_range(0.7, 1.3)),
			Vector3(_rng.randf_range(-11.4, 11.4), 0.045, _rng.randf_range(-11.4, 11.4)), shade,
			Vector3(0, _rng.randf_range(0, PI), 0))
	# Well
	solid_cyl(map, 1.3, 0.9, Vector3(0, 0.45, 0), STONE)
	PropLib.add_cyl(map, 1.1, 0.02, Vector3(0, 0.91, 0), Color(0.25, 0.45, 0.7))
	for x in [-1.1, 1.1]:
		solid(map, Vector3(0.16, 2.0, 0.16), Vector3(x, 1.9, 0), PropLib.WOOD_DARK)
	PropLib.add_cyl(map, 0.06, 2.4, Vector3(0, 2.6, 0), PropLib.WOOD, -1.0, Vector3(0, 0, PI / 2))
	PropLib.add_box(map, Vector3(2.8, 0.1, 1.2), Vector3(0, 3.1, 0.45), Color(0.6, 0.3, 0.22), Vector3(deg_to_rad(28), 0, 0))
	PropLib.add_box(map, Vector3(2.8, 0.1, 1.2), Vector3(0, 3.1, -0.45), Color(0.6, 0.3, 0.22), Vector3(deg_to_rad(-28), 0, 0))
	prop(map, "bucket", Vector3(0.75, 0.9, 0.55))
	_blocked.append(Rect2(-12, -12, 24, 24))
	# Market stalls on the plaza corners, facing the well.
	var stall_colors := [Color(0.85, 0.25, 0.25), Color(0.25, 0.5, 0.85), Color(0.95, 0.75, 0.2), Color(0.35, 0.7, 0.35)]
	var goods := [
		[["cabbage", Vector3(-0.8, 0.9, 0.5)], ["cabbage", Vector3(-0.3, 0.9, 0.55)], ["pumpkin", Vector3(0.6, 0.9, 0.5)]],
		[["basket", Vector3(-0.7, 0.9, 0.5)], ["vase", Vector3(0.2, 0.9, 0.5)], ["vase", Vector3(0.8, 0.9, 0.55)]],
		[["pumpkin", Vector3(-0.7, 0.9, 0.5)], ["pumpkin", Vector3(0.1, 0.9, 0.5)], ["basket", Vector3(0.9, 0.9, 0.5)]],
		[["small_crate", Vector3(-0.8, 0.9, 0.5)], ["bucket", Vector3(0.0, 0.9, 0.5)], ["cabbage", Vector3(0.8, 0.9, 0.5)]],
	]
	var corners := [Vector3(-8.5, 0, -8.5), Vector3(8.5, 0, -8.5), Vector3(8.5, 0, 8.5), Vector3(-8.5, 0, 8.5)]
	for i in 4:
		_stall(corners[i], stall_colors[i], goods[i])
	for p in [Vector3(11, 0, 4), Vector3(-11, 0, -4), Vector3(4, 0, -11), Vector3(-4, 0, 11)]:
		prop(map, "lantern", p)
	props(map, [
		["bench", Vector3(-4.3, 0, 0), 90], ["bench", Vector3(4.3, 0, 0), -90],
		["barrel", Vector3(-10.5, 0, -6.5)], ["barrel", Vector3(-10.4, 0, -5.6)],
		["crate", Vector3(10.4, 0, 6.6)], ["small_crate", Vector3(10.4, 0.9, 6.6), 20],
		["sack", Vector3(6.5, 0, 10.6)], ["sack", Vector3(7.2, 0, 10.8)],
	])


func _stall(pos: Vector3, cloth: Color, goods: Array) -> void:
	var stall := Node3D.new()
	stall.position = pos
	var to_centre := -pos.normalized()
	stall.rotation.y = atan2(to_centre.x, to_centre.z)
	map.add_child(stall)
	for x in [-1.4, 1.4]:
		for z in [-0.8, 0.8]:
			solid(stall, Vector3(0.12, 2.5, 0.12), Vector3(x, 1.25, z), PropLib.WOOD_DARK)
	solid(stall, Vector3(3.0, 0.9, 0.7), Vector3(0, 0.45, 0.5), PropLib.WOOD)
	for i in 4:
		var stripe := cloth if i % 2 == 0 else Color(0.96, 0.94, 0.88)
		PropLib.add_box(stall, Vector3(0.8, 0.06, 2.3), Vector3(-1.2 + i * 0.8, 2.55, 0), stripe, Vector3(deg_to_rad(12), 0, 0))
	for g in goods:
		prop(stall, g[0], g[1])
	props(stall, [["crate", Vector3(-0.8, 0, -0.9)], ["sack", Vector3(0.6, 0, -1.0)]])


func _house(pos: Vector3, yaw_deg: float, w: float, d: float, h: float, wall_color: Color, roof_color: Color, interior: Callable, door_w := 1.8, door_h := 2.4) -> void:
	var house := Node3D.new()
	house.position = pos
	house.rotation.y = deg_to_rad(yaw_deg)
	map.add_child(house)
	var t := 0.3
	var hw := w * 0.5
	var hd := d * 0.5
	var window_bottom := 1.0
	var window_top := minf(2.1, h - 0.5)
	PropLib.add_box(house, Vector3(w, 0.03, d), Vector3(0, 0.02, 0), FLOOR)
	var front := w + t
	wall(house, Vector3(-hw - t * 0.5, 0, hd), Vector3(hw + t * 0.5, 0, hd), h, wall_color, [
		[front * 0.5, door_w, 0.0, door_h],
		[front * 0.5 - w * 0.3, 1.1, window_bottom, window_top],
		[front * 0.5 + w * 0.3, 1.1, window_bottom, window_top],
	])
	wall(house, Vector3(-hw - t * 0.5, 0, -hd), Vector3(hw + t * 0.5, 0, -hd), h, wall_color, [
		[front * 0.3, 1.1, window_bottom, window_top], [front * 0.7, 1.1, window_bottom, window_top],
	])
	var side := d - t
	wall(house, Vector3(-hw, 0, -hd + t * 0.5), Vector3(-hw, 0, hd - t * 0.5), h, wall_color, [[side * 0.5, 1.1, window_bottom, window_top]])
	wall(house, Vector3(hw, 0, -hd + t * 0.5), Vector3(hw, 0, hd - t * 0.5), h, wall_color, [[side * 0.5, 1.1, window_bottom, window_top]])
	# Timber frame: corner posts and a top beam give the cottages their look.
	for x in [-hw, hw]:
		for z in [-hd, hd]:
			PropLib.add_box(house, Vector3(0.4, h, 0.4), Vector3(x, h * 0.5, z), BEAM)
	PropLib.add_box(house, Vector3(w + 0.4, 0.25, 0.38), Vector3(0, h - 0.12, hd), BEAM)
	PropLib.add_box(house, Vector3(w + 0.4, 0.25, 0.38), Vector3(0, h - 0.12, -hd), BEAM)
	PropLib.add_box(house, Vector3(door_w + 0.3, 0.2, 0.36), Vector3(0, door_h + 0.1, hd), BEAM)
	# Gable roof, ridge along x.
	var angle := deg_to_rad(32)
	var overhang := 0.6
	var run := hd + overhang
	var slab := Vector3(w + 1.0, 0.22, run / cos(angle))
	var ridge_y := h + hd * tan(angle)
	var centre_y := ridge_y - tan(angle) * run * 0.5
	solid(house, slab, Vector3(0, centre_y, run * 0.5), roof_color, Vector3(angle, 0, 0))
	solid(house, slab, Vector3(0, centre_y, -run * 0.5), roof_color, Vector3(-angle, 0, 0))
	var gable := PrismMesh.new()
	gable.size = Vector3(d, hd * tan(angle), t)
	for x in [-hw, hw]:
		var gi := MeshInstance3D.new()
		gi.mesh = gable
		gi.material_override = PropLib.material(wall_color)
		gi.position = Vector3(x, h + hd * tan(angle) * 0.5, 0)
		gi.rotation.y = PI / 2
		house.add_child(gi)
	PropLib.add_box(house, Vector3(0.5, 1.6, 0.5), Vector3(hw * 0.5, ridge_y + 0.2, -hd * 0.4), STONE.darkened(0.2))
	var light := OmniLight3D.new()
	light.position = Vector3(0, h - 0.5, 0)
	light.light_color = Color(1.0, 0.85, 0.65)
	light.light_energy = 1.4
	light.omni_range = maxf(w, d) * 0.9
	house.add_child(light)
	interior.call(house)
	var extent := Vector2(w, d) if absf(sin(deg_to_rad(yaw_deg))) < 0.5 else Vector2(d, w)
	_blocked.append(Rect2(pos.x - extent.x * 0.5 - 2.0, pos.z - extent.y * 0.5 - 2.0, extent.x + 4.0, extent.y + 4.0))


func _cottage_interior(house: Node3D) -> void:
	props(house, [
		["table", Vector3(-2, 0, -0.5)], ["chair", Vector3(-3.0, 0, -0.5), 90], ["chair", Vector3(-1.0, 0, -0.5), -90],
		["vase", Vector3(-2.3, 0.8, -0.5)], ["bookshelf", Vector3(3.2, 0, -3.6)], ["clock", Vector3(4.4, 0, -3.6)],
		["barrel", Vector3(-4.3, 0, -3.3)], ["barrel", Vector3(-4.3, 0, -2.4)], ["small_crate", Vector3(-3.4, 0, -3.4), 15],
		["bed", Vector3(3.9, 0, 1.4)], ["cauldron", Vector3(-4.0, 0, 1.4)], ["bucket", Vector3(-3.2, 0, 2.2)],
		["stool", Vector3(-2.0, 0, 2.0)], ["basket", Vector3(1.4, 0, -3.5)], ["vase", Vector3(-4.3, 0, 3.3)],
	])


func _hall_interior(house: Node3D) -> void:
	props(house, [
		["table", Vector3(-1.2, 0, 0)], ["table", Vector3(1.2, 0, 0)], ["bench", Vector3(-1.2, 0, -0.75)],
		["bench", Vector3(1.2, 0, -0.75)], ["bench", Vector3(-1.2, 0, 0.75)], ["bench", Vector3(1.2, 0, 0.75)],
		["bookshelf", Vector3(-4.6, 0, -3.6)], ["bookshelf", Vector3(-3.3, 0, -3.6)], ["clock", Vector3(0, 0, -3.6)],
		["barrel", Vector3(5.3, 0, -3.3)], ["barrel", Vector3(5.3, 0, -2.4)], ["barrel", Vector3(4.4, 0, -3.3)],
		["crate", Vector3(5.2, 0, 3.2)], ["small_crate", Vector3(5.2, 0.9, 3.2), 30], ["sack", Vector3(4.2, 0, 3.4)],
		["vase", Vector3(-5.3, 0, 3.3)], ["vase", Vector3(-4.6, 0, 3.4)], ["anvil", Vector3(3.2, 0, -3.5)],
		["cabbage", Vector3(1.0, 0.8, 0.1)], ["basket", Vector3(-1.5, 0.8, 0.1)],
	])


func _study_interior(house: Node3D) -> void:
	props(house, [
		["table", Vector3(0, 0, -2.6)], ["bench", Vector3(0, 0, -3.9)], ["chair", Vector3(-0.9, 0, -1.8), 180],
		["chair", Vector3(0.9, 0, -1.8), 180], ["bookshelf", Vector3(-4.0, 0, 1.2), 90], ["bookshelf", Vector3(-4.0, 0, 2.5), 90],
		["bed", Vector3(3.6, 0, -2.8)], ["crate", Vector3(3.7, 0, 1.5)], ["small_crate", Vector3(3.7, 0.9, 1.5), -20],
		["sack", Vector3(3.6, 0, 3.5)], ["sack", Vector3(2.9, 0, 3.7)], ["barrel", Vector3(-3.8, 0, 3.6)],
		["vase", Vector3(-2.8, 0, 3.8)], ["clock", Vector3(2.9, 0, -4.1)], ["stool", Vector3(-3.0, 0, -3.0)],
		["vase", Vector3(0.3, 0.8, -2.6)],
	])


func _barn_interior(house: Node3D) -> void:
	var list := []
	for x in [-5.8, -4.5, -3.2, 3.2, 4.5, 5.8]:
		list.append(["haybale", Vector3(x, 0, -4.4)])
	for x in [-5.8, -4.5, 4.5]:
		list.append(["haybale", Vector3(x, 0.7, -4.4)])
	list.append_array([
		["haybale", Vector3(-6.2, 0, -1.0), 90], ["haybale", Vector3(-6.2, 0, 0.4), 90], ["haybale", Vector3(-6.2, 0.7, -0.3), 90],
		["crate", Vector3(5.8, 0, 2.0)], ["crate", Vector3(5.8, 0.9, 2.0), 10], ["small_crate", Vector3(4.9, 0, 2.3)],
		["barrel", Vector3(5.9, 0, 3.5)], ["sack", Vector3(4.0, 0, 4.0)], ["bucket", Vector3(-5.0, 0, 3.0)],
		["anvil", Vector3(2.0, 0, -2.0), 30], ["logs", Vector3(-3.0, 0, 2.5)], ["basket", Vector3(-4.5, 0, 3.8)],
		["pumpkin", Vector3(0.0, 0, -1.0)], ["pumpkin", Vector3(0.8, 0, -1.4)], ["cauldron", Vector3(-1.5, 0, -3.0)],
	])
	props(house, list)


func _paths() -> void:
	var segments := [
		[Vector2(0, -12), Vector2(0, -21)], [Vector2(-8, -12), Vector2(-20, -14)], [Vector2(8, -12), Vector2(20, -14)],
		[Vector2(-12, 3), Vector2(-18.5, 10)], [Vector2(12, 3), Vector2(18.5, 10)], [Vector2(0, 12), Vector2(0, 22)],
	]
	for s in segments:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var mid := (a + b) * 0.5
		var dir := b - a
		PropLib.add_box(map, Vector3(2.4, 0.02, dir.length() + 2.0), Vector3(mid.x, 0.012, mid.y), DIRT, Vector3(0, atan2(dir.x, dir.y), 0))


func _outdoor() -> void:
	props(map, [
		# Around the cottages
		["barrel", Vector3(-14.2, 0, -15.0)], ["barrel", Vector3(-14.2, 0, -16.0)], ["crate", Vector3(-14.3, 0, -17.3), 10],
		["logs", Vector3(-26.5, 0, -17), 90], ["vase", Vector3(3, 0, -20.2)], ["vase", Vector3(3.6, 0, -20.3)],
		["bench", Vector3(-3, 0, -20.4)], ["lantern", Vector3(-1.7, 0, -20.4)], ["lantern", Vector3(1.7, 0, -20.4)],
		["crate", Vector3(14.3, 0, -15)], ["small_crate", Vector3(14.3, 0.9, -15), 25], ["barrel", Vector3(14.3, 0, -16.2)],
		["bucket", Vector3(13.7, 0, -17)], ["cauldron", Vector3(26.4, 0, -16)], ["logs", Vector3(26.5, 0, -19), 90],
		["sack", Vector3(-17.7, 0, 7.4)], ["sack", Vector3(-17.7, 0, 8.1)], ["basket", Vector3(-17.8, 0, 12.6)],
		["pumpkin", Vector3(-17.6, 0, 13.5)], ["barrel", Vector3(17.8, 0, 7.4)], ["cabbage", Vector3(17.9, 0, 12.6)],
		["cabbage", Vector3(17.5, 0, 13.1)], ["crate", Vector3(17.8, 0, 14.0), -10], ["lantern", Vector3(-17.6, 0, 11.4)],
		["lantern", Vector3(17.6, 0, 8.6)],
		# In front of the barn
		["haybale", Vector3(-5, 0, 20.8)], ["haybale", Vector3(-3.6, 0, 20.8)], ["haybale", Vector3(-4.3, 0.7, 20.8)],
		["haybale", Vector3(5, 0, 20.4), 90], ["pumpkin", Vector3(3, 0, 20.5)], ["pumpkin", Vector3(3.6, 0, 20.0)],
		["bucket", Vector3(2.2, 0, 20.8)],
		# Pond shore
		["rock", Vector3(25.2, 0, -6.5)], ["rock", Vector3(33.2, 0, -2.0), 70], ["bush", Vector3(31.5, 0, -7.6)],
		["bush", Vector3(25.0, 0, -0.5)], ["mushroom", Vector3(33.5, 0, -6.5)], ["logs", Vector3(29, 0, 1.0)],
		# Mushroom grove in the north-west corner
		["mushroom", Vector3(-29, 0, 26)], ["mushroom", Vector3(-31.5, 0, 29)], ["mushroom", Vector3(-27, 0, 30.5)],
		["mushroom", Vector3(-33, 0, 24.5)], ["mushroom", Vector3(-25.5, 0, 27.5)], ["rock", Vector3(-30, 0, 32.5)],
		["rock", Vector3(-34, 0, 27.5)], ["bush", Vector3(-26, 0, 24)], ["bush", Vector3(-32.5, 0, 32)],
		["cauldron", Vector3(-29.5, 0, 28.5)],
	])
	# Pond
	PropLib.add_box(map, Vector3(8, 0.03, 6), Vector3(29, 0.015, -3.8), Color(0.32, 0.55, 0.78))
	PropLib.add_box(map, Vector3(8.6, 0.02, 6.6), Vector3(29, 0.01, -3.8), DIRT)
	_blocked.append(Rect2(24, -8, 10, 9))
	_blocked.append(Rect2(-36, 22, 13, 13))
	# Carts and hedges for cover in the open.
	_cart(Vector3(12.5, 0, -9.5), 30)
	_cart(Vector3(-14, 0, 22), -15)
	_cart(Vector3(10, 0, 23.5), 80)
	for h in [[Vector3(-20, 0, 25), 0.0], [Vector3(15, 0, -30), 0.0], [Vector3(-32, 0, -10), 90.0], [Vector3(32, 0, 22), 90.0], [Vector3(-12, 0, -30), 20.0], [Vector3(30, 0, -24), -30.0]]:
		solid(map, Vector3(4.5, 1.3, 0.9), h[0] + Vector3(0, 0.65, 0), PropLib.LEAF.darkened(0.15), Vector3(0, deg_to_rad(h[1]), 0))


func _cart(pos: Vector3, yaw_deg: float) -> void:
	var cart := Node3D.new()
	cart.position = pos
	cart.rotation.y = deg_to_rad(yaw_deg)
	map.add_child(cart)
	solid(cart, Vector3(1.4, 0.5, 2.3), Vector3(0, 0.95, 0), PropLib.WOOD)
	PropLib.add_box(cart, Vector3(1.5, 0.3, 0.08), Vector3(0, 1.3, 1.15), PropLib.WOOD_DARK)
	PropLib.add_box(cart, Vector3(1.5, 0.3, 0.08), Vector3(0, 1.3, -1.15), PropLib.WOOD_DARK)
	for x in [-0.78, 0.78]:
		PropLib.add_cyl(cart, 0.5, 0.1, Vector3(x, 0.5, 0.2), PropLib.WOOD_DARK, -1.0, Vector3(0, 0, PI / 2))
	PropLib.add_box(cart, Vector3(0.08, 0.08, 1.6), Vector3(-0.4, 0.75, 1.9), PropLib.WOOD_DARK, Vector3(deg_to_rad(-15), 0, 0))
	PropLib.add_box(cart, Vector3(0.08, 0.08, 1.6), Vector3(0.4, 0.75, 1.9), PropLib.WOOD_DARK, Vector3(deg_to_rad(-15), 0, 0))
	props(cart, [["haybale", Vector3(0, 1.2, -0.5)], ["sack", Vector3(-0.3, 1.2, 0.6)]])


func _trees() -> void:
	var spots := [
		Vector2(-35, -35), Vector2(-28, -34), Vector2(-36, -24), Vector2(-34, -4), Vector2(-36, 6), Vector2(-35, 17),
		Vector2(-26, 35), Vector2(-16, 36), Vector2(-8, 35.5), Vector2(12, 36), Vector2(22, 35), Vector2(34, 34),
		Vector2(36, 22), Vector2(35, -12), Vector2(36, -20), Vector2(30, -35), Vector2(18, -35), Vector2(8, -36),
		Vector2(-12, -35), Vector2(-25, -28), Vector2(-31, 23), Vector2(-27, 33), Vector2(-35, 31), Vector2(-23, 29),
		Vector2(-14, 14), Vector2(14, 17), Vector2(-9, -16), Vector2(10, -18),
	]
	for i in spots.size():
		_tree(Vector3(spots[i].x, 0, spots[i].y), _rng.randf_range(0.85, 1.25), i % 3 == 0)


func _tree(pos: Vector3, s: float, pine: bool) -> void:
	solid_cyl(map, 0.28 * s, 2.4 * s, pos + Vector3(0, 1.2 * s, 0), PropLib.WOOD_DARK, 0.2 * s)
	if pine:
		for i in 3:
			var r := (1.8 - i * 0.45) * s
			PropLib.add_cyl(map, r, 1.6 * s, pos + Vector3(0, (2.4 + i * 1.0) * s, 0), Color(0.2, 0.48, 0.3), 0.0)
	else:
		var leaf := PropLib.LEAF.darkened(_rng.randf_range(0.0, 0.2))
		PropLib.add_sphere(map, 1.7 * s, pos + Vector3(0, 3.4 * s, 0), leaf)
		PropLib.add_sphere(map, 1.2 * s, pos + Vector3(0.9 * s, 2.9 * s, 0.4 * s), leaf.lightened(0.08))
		PropLib.add_sphere(map, 1.1 * s, pos + Vector3(-0.8 * s, 3.0 * s, -0.5 * s), leaf.darkened(0.05))
	_blocked.append(Rect2(pos.x - 1.5, pos.z - 1.5, 3, 3))


## Bushes, rocks and mushrooms sprinkled over the free ground.
func _scatter() -> void:
	var kinds := ["bush", "bush", "rock", "mushroom", "pumpkin", "logs"]
	var placed: Array[Vector2] = []
	var attempts := 0
	while placed.size() < 34 and attempts < 600:
		attempts += 1
		var p := Vector2(_rng.randf_range(-37, 37), _rng.randf_range(-37, 37))
		var ok := true
		for r in _blocked:
			if r.has_point(p):
				ok = false
				break
		if ok:
			for q in placed:
				if q.distance_to(p) < 3.0:
					ok = false
					break
		if not ok:
			continue
		placed.append(p)
		prop(map, kinds[_rng.randi() % kinds.size()], Vector3(p.x, 0, p.y), _rng.randf_range(0, 360))
