extends RefCounted
## Everything a hider can mimic. Props are built from primitive meshes with the
## origin at the bottom centre, so map props and disguised hiders share models.

const WOOD := Color(0.66, 0.45, 0.26)
const WOOD_DARK := Color(0.42, 0.27, 0.15)
const IRON := Color(0.26, 0.26, 0.30)
const STONE := Color(0.58, 0.58, 0.60)
const STRAW := Color(0.88, 0.75, 0.38)
const BURLAP := Color(0.78, 0.65, 0.46)
const LEAF := Color(0.30, 0.62, 0.28)
const CREAM := Color(0.95, 0.91, 0.80)
const TERRACOTTA := Color(0.80, 0.45, 0.30)
const BOOKS := [
	Color(0.72, 0.22, 0.22), Color(0.22, 0.42, 0.72), Color(0.26, 0.56, 0.32),
	Color(0.82, 0.66, 0.22), Color(0.52, 0.32, 0.62),
]

## size is the rough bounding box (it drives collisions); shape is box or cyl.
const PROPS := {
	"crate": {"name": "Crate", "size": Vector3(0.9, 0.9, 0.9), "shape": "box"},
	"small_crate": {"name": "Small crate", "size": Vector3(0.55, 0.55, 0.55), "shape": "box"},
	"barrel": {"name": "Barrel", "size": Vector3(0.8, 1.0, 0.8), "shape": "cyl"},
	"bucket": {"name": "Bucket", "size": Vector3(0.46, 0.38, 0.46), "shape": "cyl"},
	"chair": {"name": "Chair", "size": Vector3(0.5, 1.0, 0.5), "shape": "box"},
	"stool": {"name": "Stool", "size": Vector3(0.44, 0.5, 0.44), "shape": "cyl"},
	"table": {"name": "Table", "size": Vector3(1.4, 0.8, 0.8), "shape": "box"},
	"bench": {"name": "Bench", "size": Vector3(1.4, 0.5, 0.4), "shape": "box"},
	"bookshelf": {"name": "Bookshelf", "size": Vector3(1.2, 2.0, 0.4), "shape": "box"},
	"clock": {"name": "Clock", "size": Vector3(0.55, 1.9, 0.35), "shape": "box"},
	"bed": {"name": "Bed", "size": Vector3(1.0, 0.8, 2.0), "shape": "box"},
	"vase": {"name": "Vase", "size": Vector3(0.5, 0.68, 0.5), "shape": "cyl"},
	"pumpkin": {"name": "Pumpkin", "size": Vector3(0.7, 0.6, 0.7), "shape": "cyl"},
	"cabbage": {"name": "Cabbage", "size": Vector3(0.44, 0.38, 0.44), "shape": "cyl"},
	"haybale": {"name": "Hay bale", "size": Vector3(1.2, 0.7, 0.8), "shape": "box"},
	"sack": {"name": "Sack", "size": Vector3(0.6, 0.72, 0.6), "shape": "cyl"},
	"rock": {"name": "Rock", "size": Vector3(1.0, 0.6, 1.0), "shape": "cyl"},
	"bush": {"name": "Bush", "size": Vector3(1.2, 0.9, 1.2), "shape": "cyl"},
	"mushroom": {"name": "Mushroom", "size": Vector3(0.8, 0.68, 0.8), "shape": "cyl"},
	"cauldron": {"name": "Cauldron", "size": Vector3(0.9, 0.72, 0.9), "shape": "cyl"},
	"basket": {"name": "Basket", "size": Vector3(0.6, 0.56, 0.6), "shape": "cyl"},
	"lantern": {"name": "Lantern post", "size": Vector3(0.3, 1.8, 0.3), "shape": "cyl"},
	"anvil": {"name": "Anvil", "size": Vector3(0.7, 0.56, 0.35), "shape": "box"},
	"logs": {"name": "Log pile", "size": Vector3(1.2, 0.65, 0.75), "shape": "box"},
}

static var _materials := {}


static func display_name(id: String) -> String:
	return PROPS[id].name if PROPS.has(id) else id


## Radius and height of the capsule a hider uses while disguised as this prop.
static func capsule_for(id: String) -> Vector2:
	var size: Vector3 = PROPS[id].size
	var radius := maxf(minf(maxf(size.x, size.z) * 0.42, size.y * 0.5), 0.12)
	return Vector2(radius, maxf(size.y, radius * 2.0))


## A solid prop for the map (or a decoy). Hiders can mimic anything built here.
static func make_static_prop(id: String) -> StaticBody3D:
	var def: Dictionary = PROPS[id]
	var size: Vector3 = def.size
	var body := StaticBody3D.new()
	body.set_meta("prop_type", id)
	body.add_child(build_visual(id))
	var col := CollisionShape3D.new()
	if def.shape == "box":
		var box_shape := BoxShape3D.new()
		box_shape.size = size
		col.shape = box_shape
	else:
		var cyl_shape := CylinderShape3D.new()
		cyl_shape.radius = maxf(size.x, size.z) * 0.5
		cyl_shape.height = size.y
		col.shape = cyl_shape
	col.position.y = size.y * 0.5
	body.add_child(col)
	return body


# --- Mesh helpers (also used by the map and the player models) --------------

static func material(color: Color, glow := false) -> StandardMaterial3D:
	var key := color.to_html() + ("g" if glow else "")
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.85
	if glow:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = 2.5
	_materials[key] = m
	return m


static func add_box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add_mesh(parent, mesh, pos, color, rot)


static func add_cyl(parent: Node3D, radius: float, height: float, pos: Vector3, color: Color, top_radius := -1.0, rot := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top_radius < 0.0 else top_radius
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	return _add_mesh(parent, mesh, pos, color, rot)


static func add_sphere(parent: Node3D, radius: float, pos: Vector3, color: Color, scale := Vector3.ONE) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	var mi := _add_mesh(parent, mesh, pos, color, Vector3.ZERO)
	mi.scale = scale
	return mi


static func _add_mesh(parent: Node3D, mesh: Mesh, pos: Vector3, color: Color, rot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material(color)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


# --- Models ------------------------------------------------------------------

static func build_visual(id: String) -> Node3D:
	var m := Node3D.new()
	m.name = "Model"
	match id:
		"crate":
			_crate(m, 0.9)
		"small_crate":
			_crate(m, 0.55)
		"barrel":
			add_cyl(m, 0.34, 0.5, Vector3(0, 0.25, 0), WOOD, 0.4)
			add_cyl(m, 0.4, 0.5, Vector3(0, 0.75, 0), WOOD, 0.34)
			add_cyl(m, 0.33, 0.02, Vector3(0, 1.0, 0), WOOD_DARK)
			for band in [[0.12, 0.37], [0.5, 0.415], [0.88, 0.37]]:
				add_cyl(m, band[1], 0.06, Vector3(0, band[0], 0), IRON)
		"bucket":
			add_cyl(m, 0.18, 0.36, Vector3(0, 0.18, 0), Color(0.56, 0.6, 0.64), 0.23)
			add_cyl(m, 0.225, 0.04, Vector3(0, 0.3, 0), IRON)
			add_box(m, Vector3(0.03, 0.15, 0.03), Vector3(-0.22, 0.43, 0), IRON)
			add_box(m, Vector3(0.03, 0.15, 0.03), Vector3(0.22, 0.43, 0), IRON)
			add_box(m, Vector3(0.47, 0.03, 0.03), Vector3(0, 0.5, 0), IRON)
		"chair":
			for x in [-0.2, 0.2]:
				for z in [-0.2, 0.2]:
					add_box(m, Vector3(0.06, 0.45, 0.06), Vector3(x, 0.225, z), WOOD_DARK)
			add_box(m, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.47, 0), WOOD)
			add_box(m, Vector3(0.06, 0.5, 0.06), Vector3(-0.2, 0.75, -0.22), WOOD_DARK)
			add_box(m, Vector3(0.06, 0.5, 0.06), Vector3(0.2, 0.75, -0.22), WOOD_DARK)
			add_box(m, Vector3(0.5, 0.22, 0.05), Vector3(0, 0.86, -0.22), WOOD)
		"stool":
			for i in 3:
				var a := i * TAU / 3.0
				add_box(m, Vector3(0.05, 0.45, 0.05), Vector3(cos(a) * 0.14, 0.225, sin(a) * 0.14), WOOD_DARK)
			add_cyl(m, 0.22, 0.06, Vector3(0, 0.47, 0), WOOD)
		"table":
			for x in [-0.62, 0.62]:
				for z in [-0.32, 0.32]:
					add_box(m, Vector3(0.08, 0.72, 0.08), Vector3(x, 0.36, z), WOOD_DARK)
			add_box(m, Vector3(1.4, 0.08, 0.8), Vector3(0, 0.76, 0), WOOD)
		"bench":
			add_box(m, Vector3(0.07, 0.43, 0.36), Vector3(-0.55, 0.215, 0), WOOD_DARK)
			add_box(m, Vector3(0.07, 0.43, 0.36), Vector3(0.55, 0.215, 0), WOOD_DARK)
			add_box(m, Vector3(1.4, 0.07, 0.4), Vector3(0, 0.465, 0), WOOD)
		"bookshelf":
			_bookshelf(m)
		"clock":
			add_box(m, Vector3(0.5, 1.9, 0.3), Vector3(0, 0.95, 0), WOOD_DARK)
			add_box(m, Vector3(0.55, 0.08, 0.35), Vector3(0, 1.86, 0), WOOD)
			add_box(m, Vector3(0.24, 0.6, 0.02), Vector3(0, 0.8, 0.155), Color(0.8, 0.65, 0.3))
			add_cyl(m, 0.18, 0.03, Vector3(0, 1.55, 0.16), CREAM, -1.0, Vector3(PI / 2, 0, 0))
			add_box(m, Vector3(0.02, 0.13, 0.01), Vector3(0, 1.6, 0.18), IRON)
			add_box(m, Vector3(0.1, 0.02, 0.01), Vector3(0.04, 1.55, 0.18), IRON)
		"bed":
			add_box(m, Vector3(1.0, 0.35, 2.0), Vector3(0, 0.175, 0), WOOD)
			add_box(m, Vector3(0.92, 0.15, 1.85), Vector3(0, 0.42, 0.05), CREAM)
			add_box(m, Vector3(0.95, 0.09, 1.2), Vector3(0, 0.5, 0.36), Color(0.35, 0.5, 0.8))
			add_box(m, Vector3(0.6, 0.12, 0.3), Vector3(0, 0.55, -0.72), Color(1, 1, 1))
			add_box(m, Vector3(1.0, 0.8, 0.08), Vector3(0, 0.4, -0.96), WOOD_DARK)
		"vase":
			add_sphere(m, 0.25, Vector3(0, 0.26, 0), TERRACOTTA)
			add_cyl(m, 0.1, 0.2, Vector3(0, 0.55, 0), TERRACOTTA, 0.14)
			add_cyl(m, 0.16, 0.04, Vector3(0, 0.66, 0), TERRACOTTA.darkened(0.15))
		"pumpkin":
			add_sphere(m, 0.35, Vector3(0, 0.26, 0), Color(0.95, 0.52, 0.12), Vector3(1, 0.72, 1))
			add_sphere(m, 0.3, Vector3(0, 0.26, 0), Color(0.88, 0.45, 0.1), Vector3(1.22, 0.76, 0.7))
			add_cyl(m, 0.04, 0.14, Vector3(0, 0.56, 0), Color(0.3, 0.45, 0.15))
		"cabbage":
			add_sphere(m, 0.22, Vector3(0, 0.14, 0), LEAF, Vector3(1.0, 0.65, 1.0))
			add_sphere(m, 0.19, Vector3(0, 0.2, 0), Color(0.6, 0.85, 0.45))
		"haybale":
			add_box(m, Vector3(1.2, 0.7, 0.8), Vector3(0, 0.35, 0), STRAW)
			add_box(m, Vector3(0.04, 0.72, 0.82), Vector3(-0.3, 0.35, 0), Color(0.6, 0.45, 0.25))
			add_box(m, Vector3(0.04, 0.72, 0.82), Vector3(0.3, 0.35, 0), Color(0.6, 0.45, 0.25))
		"sack":
			add_sphere(m, 0.3, Vector3(0, 0.31, 0), BURLAP, Vector3(1, 1.05, 0.88))
			add_cyl(m, 0.09, 0.04, Vector3(0, 0.62, 0), WOOD_DARK)
			add_cyl(m, 0.07, 0.12, Vector3(0, 0.67, 0), BURLAP, 0.13)
		"rock":
			add_sphere(m, 0.5, Vector3(0, 0.28, 0), STONE, Vector3(1.0, 0.6, 0.85))
			add_sphere(m, 0.26, Vector3(0.3, 0.16, 0.22), STONE.darkened(0.15))
		"bush":
			add_sphere(m, 0.45, Vector3(0, 0.45, 0), LEAF)
			add_sphere(m, 0.35, Vector3(0.32, 0.35, 0.15), LEAF.lightened(0.1))
			add_sphere(m, 0.35, Vector3(-0.3, 0.38, -0.15), LEAF.darkened(0.1))
			add_sphere(m, 0.28, Vector3(0.05, 0.58, -0.25), LEAF.lightened(0.05))
		"mushroom":
			add_cyl(m, 0.13, 0.42, Vector3(0, 0.21, 0), CREAM, 0.1)
			add_sphere(m, 0.4, Vector3(0, 0.46, 0), Color(0.86, 0.2, 0.18), Vector3(1, 0.55, 1))
			for dot in [Vector3(0.15, 0.64, 0.1), Vector3(-0.18, 0.62, -0.05), Vector3(0.02, 0.66, -0.17), Vector3(-0.06, 0.61, 0.24), Vector3(0.27, 0.56, -0.12)]:
				add_sphere(m, 0.055, dot, Color(1, 1, 1))
		"cauldron":
			add_sphere(m, 0.45, Vector3(0, 0.38, 0), IRON, Vector3(1, 0.75, 1))
			add_cyl(m, 0.32, 0.06, Vector3(0, 0.64, 0), IRON.lightened(0.1))
			var brew := add_cyl(m, 0.29, 0.02, Vector3(0, 0.66, 0), Color(0.4, 0.9, 0.3))
			brew.material_override = material(Color(0.4, 0.9, 0.3), true)
			for i in 3:
				var a := i * TAU / 3.0
				add_cyl(m, 0.05, 0.12, Vector3(cos(a) * 0.25, 0.06, sin(a) * 0.25), IRON)
		"basket":
			add_cyl(m, 0.25, 0.3, Vector3(0, 0.15, 0), Color(0.72, 0.55, 0.3), 0.3)
			add_cyl(m, 0.31, 0.04, Vector3(0, 0.3, 0), Color(0.55, 0.4, 0.2))
			add_box(m, Vector3(0.04, 0.24, 0.04), Vector3(0, 0.42, -0.27), Color(0.55, 0.4, 0.2))
			add_box(m, Vector3(0.04, 0.24, 0.04), Vector3(0, 0.42, 0.27), Color(0.55, 0.4, 0.2))
			add_box(m, Vector3(0.04, 0.04, 0.58), Vector3(0, 0.54, 0), Color(0.55, 0.4, 0.2))
			for apple in [Vector3(0.08, 0.31, 0.05), Vector3(-0.08, 0.32, -0.04), Vector3(0.0, 0.33, 0.12)]:
				add_sphere(m, 0.07, apple, Color(0.85, 0.15, 0.15))
		"lantern":
			add_cyl(m, 0.14, 0.08, Vector3(0, 0.04, 0), IRON)
			add_cyl(m, 0.045, 1.4, Vector3(0, 0.74, 0), IRON)
			var lamp := add_box(m, Vector3(0.2, 0.25, 0.2), Vector3(0, 1.56, 0), Color(1.0, 0.85, 0.45))
			lamp.material_override = material(Color(1.0, 0.85, 0.45), true)
			add_cyl(m, 0.16, 0.12, Vector3(0, 1.74, 0), IRON, 0.02)
			var light := OmniLight3D.new()
			light.position = Vector3(0, 1.5, 0)
			light.light_color = Color(1.0, 0.8, 0.5)
			light.light_energy = 1.2
			light.omni_range = 5.0
			m.add_child(light)
		"anvil":
			add_box(m, Vector3(0.35, 0.22, 0.26), Vector3(0, 0.11, 0), IRON)
			add_box(m, Vector3(0.2, 0.16, 0.18), Vector3(0, 0.3, 0), IRON)
			add_box(m, Vector3(0.5, 0.16, 0.3), Vector3(-0.05, 0.46, 0), IRON.lightened(0.1))
			add_cyl(m, 0.08, 0.2, Vector3(0.3, 0.47, 0), IRON.lightened(0.1), 0.02, Vector3(0, 0, -PI / 2))
		"logs":
			for pos in [Vector3(0, 0.17, -0.19), Vector3(0, 0.17, 0.19), Vector3(0, 0.47, 0)]:
				add_cyl(m, 0.17, 1.2, pos, WOOD_DARK, -1.0, Vector3(0, 0, PI / 2))
				add_cyl(m, 0.14, 1.22, pos, WOOD.lightened(0.2), -1.0, Vector3(0, 0, PI / 2))
		_:
			add_box(m, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0), Color(1, 0, 1))
	return m


static func _crate(m: Node3D, s: float) -> void:
	add_box(m, Vector3(s, s, s), Vector3(0, s * 0.5, 0), WOOD)
	var band := Vector3(s + 0.03, s * 0.11, s + 0.03)
	add_box(m, band, Vector3(0, s * 0.08, 0), WOOD_DARK)
	add_box(m, band, Vector3(0, s * 0.92, 0), WOOD_DARK)
	var diagonal := s * 1.2
	add_box(m, Vector3(diagonal, s * 0.1, 0.02), Vector3(0, s * 0.5, s * 0.51), WOOD_DARK, Vector3(0, 0, PI / 4))
	add_box(m, Vector3(diagonal, s * 0.1, 0.02), Vector3(0, s * 0.5, -s * 0.51), WOOD_DARK, Vector3(0, 0, -PI / 4))
	add_box(m, Vector3(0.02, s * 0.1, diagonal), Vector3(s * 0.51, s * 0.5, 0), WOOD_DARK, Vector3(PI / 4, 0, 0))
	add_box(m, Vector3(0.02, s * 0.1, diagonal), Vector3(-s * 0.51, s * 0.5, 0), WOOD_DARK, Vector3(-PI / 4, 0, 0))


static func _bookshelf(m: Node3D) -> void:
	add_box(m, Vector3(1.2, 2.0, 0.04), Vector3(0, 1.0, -0.18), WOOD_DARK)
	add_box(m, Vector3(0.06, 2.0, 0.4), Vector3(-0.57, 1.0, 0), WOOD)
	add_box(m, Vector3(0.06, 2.0, 0.4), Vector3(0.57, 1.0, 0), WOOD)
	add_box(m, Vector3(1.2, 0.06, 0.4), Vector3(0, 1.97, 0), WOOD)
	var book := 0
	for shelf in 4:
		var y := 0.05 + shelf * 0.48
		add_box(m, Vector3(1.1, 0.05, 0.38), Vector3(0, y, 0), WOOD)
		var x := -0.5
		var end := 0.48 if shelf % 2 == 0 else 0.15
		while x < end:
			var w := 0.07 + 0.025 * ((book * 7) % 3)
			var h := 0.28 + 0.05 * ((book + shelf) % 3)
			add_box(m, Vector3(w - 0.01, h, 0.3), Vector3(x + w * 0.5, y + 0.025 + h * 0.5, 0.0), BOOKS[book % BOOKS.size()])
			x += w
			book += 1
