extends RefCounted
## Builds the village map from code. Everything is deterministic (fixed layout
## and a fixed random seed) so every peer ends up with the identical map.
##
## Static decoration is merged into a few big meshes and all static collisions
## live on one body, which keeps hundreds of props cheap to draw.
## Ground layers never overlap at the same height (no flickering surfaces):
##   grass 0 · paths 0.015 · house floors 0.025 · plaza base 0.03 · rugs 0.045
##   garden soil 0.05 · plaza paving 0.06

const PropLib = preload("res://scripts/world/prop_library.gd")
const MeshBatch = preload("res://scripts/world/mesh_batch.gd")

const GRASS := Color(0.47, 0.70, 0.33)
const DIRT := Color(0.64, 0.52, 0.37)
const SOIL := Color(0.42, 0.3, 0.2)
const COBBLE := Color(0.56, 0.52, 0.47)
const FLOOR := Color(0.56, 0.40, 0.26)
const BEAM := Color(0.36, 0.23, 0.14)
const STONE := Color(0.60, 0.60, 0.62)
const WATER := Color(0.32, 0.55, 0.78)
const HEDGE := Color(0.25, 0.52, 0.24)
const HALF_SIZE := 40.0
const RUGS := [Color(0.6, 0.2, 0.22), Color(0.22, 0.35, 0.6), Color(0.55, 0.45, 0.2)]

const IDENTITY := Transform3D()

var map: Node3D
var structures: StaticBody3D
var props: Array[StaticBody3D] = []
var hider_spawns: Array[Vector3] = []
var seeker_spawns: Array[Vector3] = []

var _batch := MeshBatch.new()
var _rng := RandomNumberGenerator.new()
var _taken: Array = []          # [Vector2 centre, float radius] of everything on the ground
var _zones: Array[Rect2] = []   # areas the general outdoor scatter stays out of


func build(target: Node3D) -> void:
	map = Node3D.new()
	map.name = "Map"
	target.add_child(map)
	structures = StaticBody3D.new()
	structures.name = "Structures"
	map.add_child(structures)
	_rng.seed = 20261029

	for i in 20:
		var a := i * TAU / 20.0
		hider_spawns.append(Vector3(cos(a) * 6.0, 0.1, sin(a) * 6.0))
	for i in 8:
		var a := i * TAU / 8.0 + 0.2
		seeker_spawns.append(Vector3(cos(a) * 2.4, 0.1, sin(a) * 2.4))
	_reserve(Vector2.ZERO, 7.0)  # spawn ring and well stay clear

	_ground()
	_flush("Ground")
	_boundary()
	_flush("Fence")
	_plaza()
	_flush("Plaza")
	_house(Vector3(-20, 0, -18), 0, 10, 8, 3.2, Color(0.94, 0.88, 0.74), Color(0.72, 0.3, 0.22), _kitchen)
	_house(Vector3(0, 0, -25), 0, 12, 8, 3.4, Color(0.86, 0.9, 0.95), Color(0.3, 0.42, 0.68), _tavern)
	_house(Vector3(20, 0, -18), 0, 10, 8, 3.2, Color(0.95, 0.85, 0.7), Color(0.35, 0.55, 0.32), _bedroom)
	_house(Vector3(-23, 0, 10), 90, 9, 9, 3.2, Color(0.9, 0.82, 0.72), Color(0.6, 0.35, 0.55), _study)
	_house(Vector3(23, 0, 10), -90, 9, 9, 3.2, Color(0.96, 0.92, 0.82), Color(0.75, 0.5, 0.2), _workshop)
	_house(Vector3(0, 0, 27), 180, 14, 10, 4.6, Color(0.66, 0.24, 0.18), Color(0.32, 0.22, 0.18), _barn, 3.4, 3.4)
	_paths()
	_flush("Paths")
	_garden()
	_chicken_yard()
	_storage_yard()
	_pond()
	_grove()
	_woodcutter()
	_field()
	_back_alley()
	_flush("Yards")
	_trees()
	_flush("Trees")
	_scatter()
	_flush("Scatter")


# --- Building blocks ---------------------------------------------------------

func _xf(frame: Transform3D, pos: Vector3, rot := Vector3.ZERO) -> Transform3D:
	return frame * Transform3D(Basis.from_euler(rot), pos)


## Turns everything batched so far into one mesh.
func _flush(node_name: String) -> void:
	if _batch.is_empty():
		return
	map.add_child(_batch.build_instance(node_name))
	_batch = MeshBatch.new()


func deco_box(frame: Transform3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_batch.add(mesh, _xf(frame, pos, rot), color)


func deco_cyl(frame: Transform3D, radius: float, height: float, pos: Vector3, color: Color, top := -1.0, rot := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	_batch.add(mesh, _xf(frame, pos, rot), color)


func deco_sphere(frame: Transform3D, radius: float, pos: Vector3, color: Color, scale := Vector3.ONE) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	_batch.add(mesh, _xf(frame, pos) * Transform3D(Basis.from_scale(scale), Vector3.ZERO), color)


func solid_box(frame: Transform3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	deco_box(frame, size, pos, color, rot)
	var shape := BoxShape3D.new()
	shape.size = size
	_collider(shape, _xf(frame, pos, rot))


func solid_cyl(frame: Transform3D, radius: float, height: float, pos: Vector3, color: Color, top := -1.0) -> void:
	deco_cyl(frame, radius, height, pos, color, top)
	var shape := CylinderShape3D.new()
	shape.radius = maxf(radius, top)
	shape.height = height
	_collider(shape, _xf(frame, pos))


func _collider(shape: Shape3D, xform: Transform3D) -> void:
	var col := CollisionShape3D.new()
	col.shape = shape
	col.transform = xform
	structures.add_child(col)


func prop(frame: Transform3D, id: String, pos: Vector3, yaw_deg := 0.0, reserve := true) -> void:
	var p := PropLib.make_static_prop(id)
	p.transform = _xf(frame, pos, Vector3(0, deg_to_rad(yaw_deg), 0))
	map.add_child(p)
	props.append(p)
	if reserve:
		var g := frame * pos
		_reserve(Vector2(g.x, g.z), _footprint(id))


func props_list(frame: Transform3D, list: Array) -> void:
	for e in list:
		prop(frame, e[0], e[1], e[2] if e.size() > 2 else 0.0)


## Places a prop only if its spot is free; returns whether it went down.
func try_prop(frame: Transform3D, id: String, pos: Vector3, yaw_deg: float, avoid_zones: bool) -> bool:
	var g := frame * pos
	var p2 := Vector2(g.x, g.z)
	var r := _footprint(id)
	if absf(p2.x) > HALF_SIZE - 1.5 or absf(p2.y) > HALF_SIZE - 1.5:
		return false
	if not _is_free(p2, r):
		return false
	if avoid_zones:
		for z in _zones:
			if z.grow(r).has_point(p2):
				return false
	prop(frame, id, pos, yaw_deg)
	return true


## Fills a rectangle (in the frame's space) with `count` random props.
func fill(frame: Transform3D, area: Rect2, ids: Array, count: int, avoid_zones := false) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 25:
		attempts += 1
		var id: String = ids[_rng.randi() % ids.size()]
		var pos := Vector3(_rng.randf_range(area.position.x, area.end.x), 0, _rng.randf_range(area.position.y, area.end.y))
		if try_prop(frame, id, pos, _rng.randf_range(0, 360), avoid_zones):
			placed += 1


## Scatters small items on top of a table, counter or shelf.
func on_surface(frame: Transform3D, centre: Vector3, extent: Vector2, count: int, ids: Array = PropLib.TABLETOP) -> void:
	var spots: Array[Vector2] = []
	var attempts := 0
	while spots.size() < count and attempts < count * 20:
		attempts += 1
		var id: String = ids[_rng.randi() % ids.size()]
		var r := _footprint(id)
		var s := Vector2(_rng.randf_range(-extent.x * 0.5 + r, extent.x * 0.5 - r), _rng.randf_range(-extent.y * 0.5 + r, extent.y * 0.5 - r))
		var ok := true
		for other in spots:
			if other.distance_to(s) < r + 0.14:
				ok = false
				break
		if ok:
			spots.append(s)
			prop(frame, id, centre + Vector3(s.x, 0, s.y), _rng.randf_range(0, 360), false)


func _footprint(id: String) -> float:
	var size := PropLib.size_of(id)
	return maxf(size.x, size.z) * 0.5


func _reserve(p: Vector2, r: float) -> void:
	_taken.append([p, r])


func _is_free(p: Vector2, r: float) -> bool:
	for t in _taken:
		if (t[0] as Vector2).distance_to(p) < r + t[1] + 0.15:
			return false
	return true


## A wall along from -> to with holes. Each opening is [centre, width, bottom, top]
## measured along the wall from `from`.
func _wall(frame: Transform3D, from: Vector3, to: Vector3, height: float, color: Color, openings: Array) -> void:
	var length := from.distance_to(to)
	var dir := (to - from) / length
	var yaw := atan2(-dir.z, dir.x)
	var piece := func(a: float, b: float, y0: float, y1: float) -> void:
		if b - a < 0.01 or y1 - y0 < 0.01:
			return
		var centre := from + dir * ((a + b) * 0.5) + Vector3.UP * ((y0 + y1) * 0.5)
		solid_box(frame, Vector3(b - a, y1 - y0, 0.3), centre, color, Vector3(0, yaw, 0))
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


# --- Ground, fence, plaza ----------------------------------------------------

func _ground() -> void:
	solid_box(IDENTITY, Vector3(100, 1, 100), Vector3(0, -0.5, 0), GRASS)
	# Rolling hills outside the fence, purely for the skyline.
	for i in 14:
		var a := i * TAU / 14.0 + _rng.randf_range(-0.1, 0.1)
		var r := _rng.randf_range(58.0, 70.0)
		var s := _rng.randf_range(14.0, 24.0)
		deco_sphere(IDENTITY, s, Vector3(cos(a) * r, -s * 0.55, sin(a) * r), GRASS.darkened(_rng.randf_range(0.0, 0.15)), Vector3(1.6, 1.0, 1.6))


func _boundary() -> void:
	var edge := HALF_SIZE - 0.5
	for side in 4:
		var horizontal := side < 2
		var side_sign := -1.0 if side % 2 == 0 else 1.0
		var rail_size := Vector3(HALF_SIZE * 2.0, 0.12, 0.08) if horizontal else Vector3(0.08, 0.12, HALF_SIZE * 2.0)
		for y in [0.5, 0.95]:
			var rail_pos := Vector3(0, y, side_sign * (edge + 0.1)) if horizontal else Vector3(side_sign * (edge + 0.1), y, 0)
			deco_box(IDENTITY, rail_size, rail_pos, PropLib.WOOD)
		var t := -edge
		while t <= edge:
			var post := Vector3(t, 0.6, side_sign * edge) if horizontal else Vector3(side_sign * edge, 0.6, t)
			deco_box(IDENTITY, Vector3(0.16, 1.2, 0.16), post, PropLib.WOOD_DARK)
			t += 3.0
		var wall_pos := Vector3(0, 6, side_sign * (HALF_SIZE + 1.0)) if horizontal else Vector3(side_sign * (HALF_SIZE + 1.0), 6, 0)
		var wall_size := Vector3(HALF_SIZE * 2.0 + 4.0, 12, 2) if horizontal else Vector3(2, 12, HALF_SIZE * 2.0 + 4.0)
		var shape := BoxShape3D.new()
		shape.size = wall_size
		_collider(shape, Transform3D(Basis(), wall_pos))


func _plaza() -> void:
	deco_box(IDENTITY, Vector3(24.4, 0.06, 24.4), Vector3.ZERO, COBBLE.darkened(0.25))
	# Paving stones on a regular grid with gaps, so no two stones overlap.
	var step := 1.0
	var n := 24
	for ix in n:
		for iz in n:
			var p := Vector3(-11.5 + ix * step, 0.04, -11.5 + iz * step)
			if Vector2(p.x, p.z).length() < 1.5:
				continue
			var shade := COBBLE.darkened(_rng.randf_range(-0.06, 0.12))
			deco_box(IDENTITY, Vector3(0.9, 0.04, 0.9), p, shade)
	# Well
	solid_cyl(IDENTITY, 1.3, 0.9, Vector3(0, 0.45, 0), STONE)
	deco_cyl(IDENTITY, 1.1, 0.04, Vector3(0, 0.9, 0), WATER)
	for x in [-1.1, 1.1]:
		solid_box(IDENTITY, Vector3(0.16, 2.0, 0.16), Vector3(x, 1.9, 0), PropLib.WOOD_DARK)
	deco_cyl(IDENTITY, 0.06, 2.4, Vector3(0, 2.6, 0), PropLib.WOOD, -1.0, Vector3(0, 0, PI / 2))
	deco_box(IDENTITY, Vector3(2.8, 0.1, 1.2), Vector3(0, 3.1, 0.45), Color(0.6, 0.3, 0.22), Vector3(deg_to_rad(28), 0, 0))
	deco_box(IDENTITY, Vector3(2.8, 0.1, 1.2), Vector3(0, 3.1, -0.45), Color(0.6, 0.3, 0.22), Vector3(deg_to_rad(-28), 0, 0))
	prop(IDENTITY, "bucket", Vector3(0.75, 0.9, 0.55), 0, false)

	var stall_colors := [Color(0.85, 0.25, 0.25), Color(0.25, 0.5, 0.85), Color(0.95, 0.75, 0.2), Color(0.35, 0.7, 0.35)]
	var corners := [Vector3(-8.5, 0, -8.5), Vector3(8.5, 0, -8.5), Vector3(8.5, 0, 8.5), Vector3(-8.5, 0, 8.5)]
	for i in 4:
		_stall(corners[i], stall_colors[i])
	for p in [Vector3(11.4, 0, 4), Vector3(-11.4, 0, -4), Vector3(4, 0, -11.4), Vector3(-4, 0, 11.4)]:
		prop(IDENTITY, "lantern", p)
	props_list(IDENTITY, [
		["bench", Vector3(-7.6, 0, 1.5), 90], ["bench", Vector3(7.6, 0, -1.5), -90],
		["bench", Vector3(1.5, 0, 7.6), 180], ["bench", Vector3(-1.5, 0, -7.6), 0],
	])
	# Market clutter around the edge of the square.
	var goods := ["barrel", "crate", "small_crate", "sack", "basket", "bucket", "flower_pot", "pumpkin",
		"cabbage", "keg", "potted_plant", "vase", "milk_can", "jug", "cheese", "watering_can"]
	fill(IDENTITY, Rect2(-11.8, -11.8, 23.6, 23.6), goods, 38)
	_zones.append(Rect2(-12.5, -12.5, 25, 25))


func _stall(pos: Vector3, cloth: Color) -> void:
	var to_centre := -pos.normalized()
	var frame := Transform3D(Basis.from_euler(Vector3(0, atan2(to_centre.x, to_centre.z), 0)), pos)
	for x in [-1.4, 1.4]:
		for z in [-0.8, 0.8]:
			solid_box(frame, Vector3(0.12, 2.5, 0.12), Vector3(x, 1.25, z), PropLib.WOOD_DARK)
	solid_box(frame, Vector3(3.0, 0.9, 0.7), Vector3(0, 0.45, 0.5), PropLib.WOOD)
	for i in 4:
		var stripe := cloth if i % 2 == 0 else Color(0.96, 0.94, 0.88)
		deco_box(frame, Vector3(0.8, 0.06, 2.3), Vector3(-1.2 + i * 0.8, 2.55, 0), stripe, Vector3(deg_to_rad(12), 0, 0))
	var g := frame * Vector3.ZERO
	_reserve(Vector2(g.x, g.z), 1.9)
	on_surface(frame, Vector3(0, 0.9, 0.5), Vector2(2.9, 0.6), 6,
		["cabbage", "pumpkin", "basket", "cheese", "bread", "jug", "bottle", "plates", "mug", "flower_pot"])
	props_list(frame, [["crate", Vector3(-0.8, 0, -1.4)], ["sack", Vector3(0.7, 0, -1.5)], ["small_crate", Vector3(-0.8, 0.9, -1.4), 20]])


# --- Buildings ---------------------------------------------------------------

func _house(pos: Vector3, yaw_deg: float, w: float, d: float, h: float, wall_color: Color, roof_color: Color, interior: Callable, door_w := 1.8, door_h := 2.4) -> void:
	var frame := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw_deg), 0)), pos)
	var t := 0.3
	var hw := w * 0.5
	var hd := d * 0.5
	var window_bottom := 1.0
	var window_top := minf(2.1, h - 0.5)
	deco_box(frame, Vector3(w, 0.05, d), Vector3.ZERO, FLOOR)
	deco_box(frame, Vector3(w * 0.45, 0.04, d * 0.4), Vector3(0, 0.025, 0.3), RUGS[int(absf(pos.x + pos.z)) % RUGS.size()])
	var front := w + t
	_wall(frame, Vector3(-hw - t * 0.5, 0, hd), Vector3(hw + t * 0.5, 0, hd), h, wall_color, [
		[front * 0.5, door_w, 0.0, door_h],
		[front * 0.5 - w * 0.3, 1.1, window_bottom, window_top],
		[front * 0.5 + w * 0.3, 1.1, window_bottom, window_top],
	])
	_wall(frame, Vector3(-hw - t * 0.5, 0, -hd), Vector3(hw + t * 0.5, 0, -hd), h, wall_color, [
		[front * 0.3, 1.1, window_bottom, window_top], [front * 0.7, 1.1, window_bottom, window_top],
	])
	var side := d - t
	_wall(frame, Vector3(-hw, 0, -hd + t * 0.5), Vector3(-hw, 0, hd - t * 0.5), h, wall_color, [[side * 0.5, 1.1, window_bottom, window_top]])
	_wall(frame, Vector3(hw, 0, -hd + t * 0.5), Vector3(hw, 0, hd - t * 0.5), h, wall_color, [[side * 0.5, 1.1, window_bottom, window_top]])
	# Timber frame: posts and beams stand clear of the wall faces.
	for x in [-hw, hw]:
		for z in [-hd, hd]:
			deco_box(frame, Vector3(0.42, h + 0.02, 0.42), Vector3(x, h * 0.5, z), BEAM)
	for z in [-hd, hd]:
		deco_box(frame, Vector3(w + 0.38, 0.26, 0.4), Vector3(0, h - 0.13, z), BEAM)
	deco_box(frame, Vector3(door_w + 0.3, 0.2, 0.38), Vector3(0, door_h + 0.1, hd), BEAM)
	# Gable roof, ridge along x.
	var angle := deg_to_rad(32)
	var overhang := 0.6
	var run := hd + overhang
	var slab := Vector3(w + 1.0, 0.22, run / cos(angle))
	var rise := hd * tan(angle)
	var centre_y := h + rise - tan(angle) * run * 0.5 + 0.12
	solid_box(frame, slab, Vector3(0, centre_y, run * 0.5), roof_color, Vector3(angle, 0, 0))
	solid_box(frame, slab, Vector3(0, centre_y, -run * 0.5), roof_color.darkened(0.08), Vector3(-angle, 0, 0))
	var gable := PrismMesh.new()
	gable.size = Vector3(d - 0.1, rise, t)
	for x in [-hw, hw]:
		_batch.add(gable, _xf(frame, Vector3(x, h + rise * 0.5, 0), Vector3(0, PI / 2, 0)), wall_color)
	deco_box(frame, Vector3(0.5, 1.6, 0.5), Vector3(hw * 0.5, h + rise + 0.2, -hd * 0.4), STONE.darkened(0.2))
	var light := OmniLight3D.new()
	light.position = frame * Vector3(0, h - 0.5, 0)
	light.light_color = Color(1.0, 0.85, 0.65)
	light.light_energy = 1.4
	light.omni_range = maxf(w, d) * 0.9
	map.add_child(light)
	# Keep the doorway clear inside and out.
	for z in [hd - 0.7, hd + 1.4]:
		var g := frame * Vector3(0, 0, z)
		_reserve(Vector2(g.x, g.z), door_w * 0.6)
	_flush("HouseShell")
	interior.call(frame, w, d)
	_flush("HouseInterior")
	var extent := Vector2(w, d) if absf(sin(deg_to_rad(yaw_deg))) < 0.5 else Vector2(d, w)
	_zones.append(Rect2(pos.x - extent.x * 0.5 - 1.5, pos.z - extent.y * 0.5 - 1.5, extent.x + 3.0, extent.y + 3.0))
	# Outside the front door: a mailbox and a lantern.
	prop(frame, "mailbox", Vector3(door_w * 0.5 + 1.0, 0, hd + 1.0), 0)


## Random floor clutter inside a room, keeping clear of the furniture.
func _room_clutter(frame: Transform3D, w: float, d: float, ids: Array, count: int) -> void:
	fill(frame, Rect2(-w * 0.5 + 0.5, -d * 0.5 + 0.5, w - 1.0, d - 1.0), ids, count)


func _kitchen(f: Transform3D, w: float, d: float) -> void:
	props_list(f, [
		["table", Vector3(-2, 0, -0.3)], ["chair", Vector3(-3.0, 0, -0.3), 90], ["chair", Vector3(-1.0, 0, -0.3), -90],
		["cupboard", Vector3(2.9, 0, -3.55)], ["clock", Vector3(4.4, 0, -3.65)], ["barrel", Vector3(-4.3, 0, -3.3)],
		["barrel", Vector3(-4.3, 0, -2.4)], ["cauldron", Vector3(-4.1, 0, 1.4)], ["round_table", Vector3(2.4, 0, 0.6)],
		["stool", Vector3(1.4, 0, 0.6)], ["stool", Vector3(3.4, 0, 0.6)], ["armchair", Vector3(4.1, 0, 2.7), -120],
	])
	prop(f, "keg", Vector3(-4.3, 1.0, -3.3), 0, false)
	on_surface(f, Vector3(-2, 0.8, -0.3), Vector2(1.3, 0.7), 5)
	on_surface(f, Vector3(2.4, 0.78, 0.6), Vector2(0.8, 0.8), 3)
	on_surface(f, Vector3(2.9, 1.0, -3.4), Vector2(1.0, 0.18), 2, ["jug", "bottle", "mug", "candle"])
	_room_clutter(f, w, d, ["bucket", "sack", "basket", "small_crate", "broom", "flower_pot", "potted_plant",
		"cooking_pot", "jug", "milk_can", "cabbage", "pumpkin"], 12)


func _tavern(f: Transform3D, w: float, d: float) -> void:
	solid_box(f, Vector3(6.0, 1.0, 0.6), Vector3(-2.0, 0.5, -2.6), PropLib.WOOD_DARK)
	deco_box(f, Vector3(6.1, 0.06, 0.7), Vector3(-2.0, 1.03, -2.6), PropLib.WOOD)
	var g := f * Vector3(-2.0, 0, -2.6)
	_reserve(Vector2(g.x, g.z), 0.5)
	for x in [-4.6, -3.6, -2.6, -1.6, -0.6, 0.4]:
		prop(f, "keg", Vector3(x, 0, -3.55))
	on_surface(f, Vector3(-2.0, 1.06, -2.6), Vector2(5.8, 0.5), 10, ["mug", "bottle", "jug", "plates", "candle", "bread", "cheese"])
	props_list(f, [
		["round_table", Vector3(3.6, 0, -1.6)], ["round_table", Vector3(3.6, 0, 1.9)], ["table", Vector3(-2.6, 0, 1.2)],
		["bench", Vector3(-2.6, 0, 0.45)], ["bench", Vector3(-2.6, 0, 1.95)],
		["stool", Vector3(2.5, 0, -1.6)], ["stool", Vector3(4.7, 0, -1.6)], ["stool", Vector3(3.6, 0, -0.5)],
		["stool", Vector3(2.5, 0, 1.9)], ["stool", Vector3(4.7, 0, 1.9)], ["barrel", Vector3(5.4, 0, -3.4)],
		["barrel", Vector3(4.5, 0, -3.4)], ["crate", Vector3(5.3, 0, 3.2)], ["clock", Vector3(2.0, 0, -3.65)],
	])
	prop(f, "small_crate", Vector3(5.3, 0.9, 3.2), 25, false)
	on_surface(f, Vector3(3.6, 0.78, -1.6), Vector2(0.8, 0.8), 4)
	on_surface(f, Vector3(3.6, 0.78, 1.9), Vector2(0.8, 0.8), 4)
	on_surface(f, Vector3(-2.6, 0.8, 1.2), Vector2(1.3, 0.7), 5)
	_room_clutter(f, w, d, ["keg", "bucket", "sack", "broom", "mug", "bottle", "small_crate", "jug", "candle"], 10)


func _bedroom(f: Transform3D, w: float, d: float) -> void:
	props_list(f, [
		["bed", Vector3(-3.9, 0, -2.8)], ["bed", Vector3(-1.6, 0, -2.8)], ["nightstand", Vector3(-2.75, 0, -3.55)],
		["wardrobe", Vector3(3.6, 0, -3.5)], ["chest", Vector3(1.4, 0, -3.5)], ["chest", Vector3(-3.9, 0, -1.3)],
		["armchair", Vector3(3.9, 0, 0.3), -90], ["coat_rack", Vector3(4.4, 0, 3.4)], ["toy_horse", Vector3(1.8, 0, 1.4), 40],
	])
	prop(f, "table_lamp", Vector3(-2.75, 0.6, -3.55), 0, false)
	prop(f, "pillow", Vector3(-1.6, 0.56, -3.4), 0, false)
	prop(f, "pillow", Vector3(-3.9, 0.56, -3.4), 0, false)
	on_surface(f, Vector3(1.4, 0.68, -3.5), Vector2(0.7, 0.4), 2, ["candle", "books", "hourglass", "flower_pot"])
	_room_clutter(f, w, d, ["pillow", "books", "toy_horse", "basket", "flower_pot", "potted_plant", "candle",
		"small_crate", "birdcage", "chest", "stool"], 12)


func _study(f: Transform3D, w: float, d: float) -> void:
	props_list(f, [
		["bookshelf", Vector3(-3.4, 0, -4.1)], ["bookshelf", Vector3(-2.1, 0, -4.1)], ["bookshelf", Vector3(-0.8, 0, -4.1)],
		["bookshelf", Vector3(-4.0, 0, 1.0), 90], ["table", Vector3(2.2, 0, -3.3)], ["chair", Vector3(2.2, 0, -2.5), 180],
		["clock", Vector3(4.0, 0, -4.1)], ["armchair", Vector3(1.2, 0, 2.3), 120], ["armchair", Vector3(3.9, 0, 1.2), -150],
		["round_table", Vector3(2.7, 0, 3.0)], ["globe", Vector3(-3.6, 0, 3.5)], ["birdcage", Vector3(-3.9, 0, 2.7)],
	])
	on_surface(f, Vector3(2.2, 0.8, -3.3), Vector2(1.3, 0.7), 5, ["books", "candle", "hourglass", "globe", "table_lamp", "mug", "bottle"])
	on_surface(f, Vector3(2.7, 0.78, 3.0), Vector2(0.8, 0.8), 3, ["books", "candle", "mug", "jug", "flower_pot"])
	_room_clutter(f, w, d, ["books", "candle", "potted_plant", "chest", "stool", "globe", "flower_pot", "pillow", "small_crate"], 12)


func _workshop(f: Transform3D, w: float, d: float) -> void:
	props_list(f, [
		["table", Vector3(-2.6, 0, -3.6)], ["table", Vector3(-0.8, 0, -3.6)], ["anvil", Vector3(1.6, 0, -2.4), 20],
		["grindstone", Vector3(3.4, 0, -3.6)], ["firewood", Vector3(3.7, 0, 0.4), 90], ["logs", Vector3(3.7, 0, 2.6), 90],
		["barrel", Vector3(-3.8, 0, -0.6)], ["barrel", Vector3(-3.8, 0, 0.4)], ["crate", Vector3(-3.7, 0, 2.6)],
		["broom", Vector3(-4.0, 0, 3.8)], ["cartwheel", Vector3(4.2, 0, -1.6), 90],
	])
	prop(f, "small_crate", Vector3(-3.7, 0.9, 2.6), 15, false)
	on_surface(f, Vector3(-2.6, 0.8, -3.6), Vector2(1.3, 0.7), 4, ["cooking_pot", "kettle", "bottle", "jug", "candle", "hourglass", "books"])
	on_surface(f, Vector3(-0.8, 0.8, -3.6), Vector2(1.3, 0.7), 4, ["cooking_pot", "kettle", "bottle", "jug", "candle", "bucket"])
	_room_clutter(f, w, d, ["bucket", "sack", "small_crate", "keg", "watering_can", "cooking_pot", "broom", "stump", "milk_can"], 12)


func _barn(f: Transform3D, w: float, d: float) -> void:
	for x in [-5.8, -4.5, -3.2, 3.2, 4.5, 5.8]:
		prop(f, "haybale", Vector3(x, 0, -4.4))
	for x in [-5.8, -4.5, 4.5]:
		prop(f, "haybale", Vector3(x, 0.7, -4.4), 0, false)
	props_list(f, [
		["haybale", Vector3(-6.2, 0, -1.0), 90], ["haybale", Vector3(-6.2, 0, 0.4), 90], ["haystack", Vector3(-4.2, 0, 1.4)],
		["trough", Vector3(4.6, 0, -1.6)], ["milk_can", Vector3(6.1, 0, 1.6)], ["milk_can", Vector3(6.2, 0, 2.3)],
		["wheelbarrow", Vector3(2.6, 0, 2.4), 30], ["crate", Vector3(5.8, 0, 3.6)], ["cartwheel", Vector3(6.6, 0, -2.4), 90],
	])
	prop(f, "haybale", Vector3(-6.2, 0.7, -0.3), 90, false)
	prop(f, "crate", Vector3(5.8, 0.9, 3.6), 10, false)
	_room_clutter(f, w, d, ["chicken", "chicken", "sack", "bucket", "pumpkin", "milk_can", "haybale", "small_crate",
		"basket", "watering_can", "broom"], 16)


func _paths() -> void:
	# [from, to]; each stops 0.2 m short of the door so it never overlaps a floor.
	var segments := [
		[Vector2(0, -12), Vector2(0, -20.8)], [Vector2(-8, -12), Vector2(-20, -13.8)], [Vector2(8, -12), Vector2(20, -13.8)],
		[Vector2(-12, 3), Vector2(-18.3, 10)], [Vector2(12, 3), Vector2(18.3, 10)], [Vector2(0, 12), Vector2(0, 21.8)],
	]
	for s in segments:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var mid := (a + b) * 0.5
		var dir := b - a
		deco_box(IDENTITY, Vector3(2.4, 0.03, dir.length()), Vector3(mid.x, 0, mid.y), DIRT, Vector3(0, atan2(dir.x, dir.y), 0))


# --- Outdoor areas -----------------------------------------------------------

## A fenced rectangle made of fence props, with a gap for the gate.
func _fence_ring(area: Rect2, gate_side: int, gate_at: float) -> void:
	var sides := [
		[area.position, Vector2(area.end.x, area.position.y)],
		[Vector2(area.position.x, area.end.y), area.end],
		[area.position, Vector2(area.position.x, area.end.y)],
		[Vector2(area.end.x, area.position.y), area.end],
	]
	for i in 4:
		var a: Vector2 = sides[i][0]
		var b: Vector2 = sides[i][1]
		var length := a.distance_to(b)
		var dir := (b - a) / length
		var count := int(length / 1.6)
		for k in count:
			var t := 0.8 + k * 1.6
			if i == gate_side and absf(t - gate_at) < 1.3:
				continue
			var p := a + dir * t
			var yaw := rad_to_deg(atan2(-dir.y, dir.x))
			prop(IDENTITY, "fence", Vector3(p.x, 0, p.y), yaw, false)


func _garden() -> void:
	var area := Rect2(13, 19, 21, 15)
	_zones.append(area.grow(0.8))
	_fence_ring(area, 0, 4.0)
	for row in 4:
		var z := 21.6 + row * 3.0
		deco_box(IDENTITY, Vector3(12, 0.1, 1.6), Vector3(23.5, 0, z), SOIL)
		for x in [17.4, 29.6]:
			deco_box(IDENTITY, Vector3(0.1, 0.16, 1.7), Vector3(x, 0.03, z), PropLib.WOOD_DARK)
		var crop: String = ["cabbage", "pumpkin", "sunflower", "cabbage"][row]
		var x := 18.2
		while x < 29.0:
			prop(IDENTITY, crop, Vector3(x + _rng.randf_range(-0.1, 0.1), 0.05, z + _rng.randf_range(-0.2, 0.2)), _rng.randf_range(0, 360))
			x += 0.9 if crop != "pumpkin" else 1.1
	props_list(IDENTITY, [
		["scarecrow", Vector3(31.5, 0, 26.5), -90], ["beehive", Vector3(32.6, 0, 32.5)], ["beehive", Vector3(31.4, 0, 32.7)],
		["beehive", Vector3(32.8, 0, 31.2)], ["wheelbarrow", Vector3(15.0, 0, 32.0), 150], ["birdhouse", Vector3(14.2, 0, 20.4)],
	])
	fill(IDENTITY, Rect2(13.6, 19.6, 3.4, 13.8), ["watering_can", "gnome", "flower_pot", "bucket", "basket", "sack", "pumpkin"], 12)
	fill(IDENTITY, Rect2(30.0, 19.6, 3.4, 13.8), ["watering_can", "gnome", "flower_pot", "bucket", "basket", "haybale"], 8)


func _chicken_yard() -> void:
	var area := Rect2(-16, 20, 8, 11)
	_zones.append(area.grow(0.8))
	_fence_ring(area, 3, 5.0)
	props_list(IDENTITY, [["trough", Vector3(-12, 0, 29.8)], ["haystack", Vector3(-14.4, 0, 21.8)]])
	fill(IDENTITY, area.grow(-0.6), ["chicken", "chicken", "chicken", "bucket", "milk_can", "sack", "haybale", "basket"], 18)


func _storage_yard() -> void:
	var area := Rect2(8, -37.5, 22, 9)
	_zones.append(area.grow(0.5))
	_cart(Vector3(12, 0, -33), 10)
	_cart(Vector3(25, 0, -31), -70)
	# Crate stacks
	for spot in [Vector3(16, 0, -35.5), Vector3(19, 0, -35.5), Vector3(22, 0, -35.5), Vector3(28, 0, -35)]:
		prop(IDENTITY, "crate", spot, _rng.randf_range(-10, 10))
		prop(IDENTITY, "crate", spot + Vector3(0, 0.9, 0), _rng.randf_range(-15, 15), false)
		if _rng.randf() < 0.6:
			prop(IDENTITY, "small_crate", spot + Vector3(0, 1.8, 0), _rng.randf_range(0, 90), false)
	fill(IDENTITY, area, ["barrel", "keg", "crate", "small_crate", "sack", "logs", "firewood", "bucket", "broom"], 34)


func _pond() -> void:
	deco_box(IDENTITY, Vector3(8, 0.04, 6), Vector3(29, 0, -3), WATER)
	_zones.append(Rect2(25, -6, 8, 6))
	_reserve(Vector2(29, -3), 3.6)
	var ring := ["rock", "small_rock", "fern", "small_rock", "stump", "mushroom", "fern", "bush"]
	for i in 18:
		var a := i * TAU / 18.0 + _rng.randf_range(-0.1, 0.1)
		var p := Vector3(29 + cos(a) * 5.2, 0, -3 + sin(a) * 4.0)
		try_prop(IDENTITY, ring[i % ring.size()], p, _rng.randf_range(0, 360), false)


func _grove() -> void:
	var area := Rect2(-37.5, 22, 13, 15.5)
	for p in [Vector2(-31, 23.5), Vector2(-27, 27), Vector2(-35, 31), Vector2(-28.5, 34), Vector2(-33.5, 25.5)]:
		_tree(Vector3(p.x, 0, p.y), _rng.randf_range(0.9, 1.2), false)
	prop(IDENTITY, "cauldron", Vector3(-30.5, 0, 29.5))
	fill(IDENTITY, area, ["mushroom", "mushroom", "fern", "stump", "rock", "small_rock", "gnome", "bush"], 30)
	_zones.append(area)


func _woodcutter() -> void:
	var area := Rect2(-37.5, -37.5, 12, 12)
	props_list(IDENTITY, [["firewood", Vector3(-32, 0, -36), 0], ["firewood", Vector3(-30.4, 0, -36), 0], ["wheelbarrow", Vector3(-27, 0, -33), 60]])
	fill(IDENTITY, area, ["stump", "stump", "logs", "firewood", "small_crate", "broom", "bucket", "rock"], 22)
	_zones.append(area)


func _field() -> void:
	var area := Rect2(-37.5, -12, 9, 30)
	props_list(IDENTITY, [["scarecrow", Vector3(-33, 0, -2), 90], ["scarecrow", Vector3(-33, 0, 11), 90], ["signpost", Vector3(-29, 0, 3.5), 90]])
	fill(IDENTITY, area, ["haystack", "haybale", "haybale", "pumpkin", "sack", "wheelbarrow", "small_rock"], 22)
	_zones.append(area)


func _back_alley() -> void:
	var area := Rect2(-12, -38, 18, 7)
	fill(IDENTITY, area, ["barrel", "crate", "sack", "broom", "bucket", "small_crate", "keg", "logs", "cartwheel"], 20)
	_zones.append(area)


func _cart(pos: Vector3, yaw_deg: float) -> void:
	var f := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(yaw_deg), 0)), pos)
	solid_box(f, Vector3(1.4, 0.5, 2.3), Vector3(0, 0.95, 0), PropLib.WOOD)
	deco_box(f, Vector3(1.5, 0.3, 0.08), Vector3(0, 1.3, 1.17), PropLib.WOOD_DARK)
	deco_box(f, Vector3(1.5, 0.3, 0.08), Vector3(0, 1.3, -1.17), PropLib.WOOD_DARK)
	for x in [-0.78, 0.78]:
		deco_cyl(f, 0.5, 0.1, Vector3(x, 0.5, 0.2), PropLib.WOOD_DARK, -1.0, Vector3(0, 0, PI / 2))
	deco_box(f, Vector3(0.08, 0.08, 1.6), Vector3(-0.4, 0.75, 1.9), PropLib.WOOD_DARK, Vector3(deg_to_rad(-15), 0, 0))
	deco_box(f, Vector3(0.08, 0.08, 1.6), Vector3(0.4, 0.75, 1.9), PropLib.WOOD_DARK, Vector3(deg_to_rad(-15), 0, 0))
	var g := f * Vector3.ZERO
	_reserve(Vector2(g.x, g.z), 1.6)
	prop(f, "haybale", Vector3(0, 1.2, -0.5), 0, false)
	prop(f, "sack", Vector3(-0.3, 1.2, 0.6), 0, false)


func _trees() -> void:
	var spots := [
		Vector2(-35, -20), Vector2(-36, -24), Vector2(-34, -4), Vector2(-24, -30), Vector2(-14, -32),
		Vector2(-16, 36), Vector2(-8, 35.5), Vector2(10, 36.5), Vector2(36, 18), Vector2(35, 5),
		Vector2(35, -12), Vector2(36, -20), Vector2(34, -26), Vector2(-17, -27), Vector2(-14, 14),
		Vector2(14, 16.5), Vector2(-9, -16), Vector2(10, -18), Vector2(-24, -6), Vector2(25, -8.5),
		Vector2(-6, 17), Vector2(6, 17), Vector2(-34, 19), Vector2(37, 37),
	]
	for i in spots.size():
		var p := Vector3(spots[i].x, 0, spots[i].y)
		_tree(p, _rng.randf_range(0.85, 1.25), i % 3 == 0)
	for h in [[Vector3(-20, 0, 24.5), 0.0], [Vector3(-32, 0, -10), 90.0], [Vector3(-12, 0, -29.2), 0.0], [Vector3(31, 0, -24), -30.0], [Vector3(10, 0, 33), 0.0]]:
		var f := Transform3D(Basis.from_euler(Vector3(0, deg_to_rad(h[1]), 0)), h[0])
		solid_box(f, Vector3(4.5, 1.3, 0.9), Vector3(0, 0.65, 0), HEDGE)
		var g: Vector3 = h[0]
		_reserve(Vector2(g.x, g.z), 2.3)


func _tree(pos: Vector3, s: float, pine: bool) -> void:
	solid_cyl(IDENTITY, 0.28 * s, 2.4 * s, pos + Vector3(0, 1.2 * s, 0), PropLib.WOOD_DARK, 0.2 * s)
	if pine:
		for i in 3:
			deco_cyl(IDENTITY, (1.8 - i * 0.45) * s, 1.6 * s, pos + Vector3(0, (2.4 + i * 1.0) * s, 0), Color(0.2, 0.48, 0.3), 0.0)
	else:
		var leaf := PropLib.LEAF.darkened(_rng.randf_range(0.0, 0.2))
		deco_sphere(IDENTITY, 1.7 * s, pos + Vector3(0, 3.4 * s, 0), leaf)
		deco_sphere(IDENTITY, 1.2 * s, pos + Vector3(0.9 * s, 2.9 * s, 0.4 * s), leaf.lightened(0.08))
		deco_sphere(IDENTITY, 1.1 * s, pos + Vector3(-0.8 * s, 3.0 * s, -0.5 * s), leaf.darkened(0.05))
	_reserve(Vector2(pos.x, pos.z), 0.6 * s)


## Bushes, rocks and odds and ends over all the remaining free ground.
func _scatter() -> void:
	var kinds := ["bush", "bush", "rock", "small_rock", "fern", "fern", "stump", "mushroom", "flower_pot",
		"gnome", "birdhouse", "sack", "barrel", "crate", "pumpkin", "signpost", "lantern", "logs", "haybale"]
	fill(IDENTITY, Rect2(-38, -38, 76, 76), kinds, 130, true)
