extends RefCounted
## Everything a hider can mimic. Each prop is built from coloured primitives,
## merged into one mesh and cached, with its origin at the bottom centre so map
## props, decoys and disguised hiders all share the same model.
## Details that sit on a surface stand at least 2 cm proud of it, so nothing
## flickers (z-fights) at a distance.

const MeshBatch = preload("res://scripts/world/mesh_batch.gd")

const WOOD := Color(0.66, 0.45, 0.26)
const WOOD_DARK := Color(0.42, 0.27, 0.15)
const WOOD_LIGHT := Color(0.8, 0.62, 0.4)
const IRON := Color(0.26, 0.26, 0.30)
const BRASS := Color(0.82, 0.66, 0.3)
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

## size is the rough bounding box (it drives collisions and health); shape is box or cyl.
const PROPS := {
	# Furniture
	"chair": {"name": "Chair", "size": Vector3(0.5, 1.0, 0.5), "shape": "box"},
	"stool": {"name": "Stool", "size": Vector3(0.44, 0.5, 0.44), "shape": "cyl"},
	"table": {"name": "Table", "size": Vector3(1.4, 0.8, 0.8), "shape": "box"},
	"round_table": {"name": "Round table", "size": Vector3(1.1, 0.78, 1.1), "shape": "cyl"},
	"bench": {"name": "Bench", "size": Vector3(1.4, 0.5, 0.4), "shape": "box"},
	"armchair": {"name": "Armchair", "size": Vector3(0.85, 1.0, 0.8), "shape": "box"},
	"bookshelf": {"name": "Bookshelf", "size": Vector3(1.2, 2.0, 0.4), "shape": "box"},
	"cupboard": {"name": "Cupboard", "size": Vector3(1.1, 1.82, 0.54), "shape": "box"},
	"wardrobe": {"name": "Wardrobe", "size": Vector3(1.28, 2.1, 0.66), "shape": "box"},
	"nightstand": {"name": "Nightstand", "size": Vector3(0.54, 0.6, 0.49), "shape": "box"},
	"clock": {"name": "Clock", "size": Vector3(0.55, 1.9, 0.35), "shape": "box"},
	"bed": {"name": "Bed", "size": Vector3(1.0, 0.8, 2.0), "shape": "box"},
	"chest": {"name": "Chest", "size": Vector3(0.9, 0.68, 0.6), "shape": "box"},
	"coat_rack": {"name": "Coat rack", "size": Vector3(0.5, 1.85, 0.5), "shape": "cyl"},
	"pillow": {"name": "Pillow", "size": Vector3(0.5, 0.16, 0.35), "shape": "box"},
	"toy_horse": {"name": "Toy horse", "size": Vector3(0.6, 0.62, 0.25), "shape": "box"},
	# Tableware and small things
	"mug": {"name": "Mug", "size": Vector3(0.2, 0.16, 0.16), "shape": "cyl"},
	"bottle": {"name": "Bottle", "size": Vector3(0.14, 0.36, 0.14), "shape": "cyl"},
	"jug": {"name": "Jug", "size": Vector3(0.34, 0.42, 0.3), "shape": "cyl"},
	"plates": {"name": "Plates", "size": Vector3(0.32, 0.12, 0.32), "shape": "cyl"},
	"bread": {"name": "Bread", "size": Vector3(0.36, 0.16, 0.2), "shape": "box"},
	"cheese": {"name": "Cheese wheel", "size": Vector3(0.46, 0.21, 0.46), "shape": "cyl"},
	"kettle": {"name": "Kettle", "size": Vector3(0.4, 0.33, 0.3), "shape": "cyl"},
	"candle": {"name": "Candle", "size": Vector3(0.12, 0.3, 0.12), "shape": "cyl"},
	"cooking_pot": {"name": "Cooking pot", "size": Vector3(0.52, 0.3, 0.44), "shape": "cyl"},
	"books": {"name": "Book pile", "size": Vector3(0.35, 0.28, 0.25), "shape": "box"},
	"globe": {"name": "Globe", "size": Vector3(0.4, 0.6, 0.4), "shape": "cyl"},
	"birdcage": {"name": "Birdcage", "size": Vector3(0.36, 0.62, 0.36), "shape": "cyl"},
	"hourglass": {"name": "Hourglass", "size": Vector3(0.2, 0.32, 0.2), "shape": "cyl"},
	"table_lamp": {"name": "Table lamp", "size": Vector3(0.3, 0.46, 0.3), "shape": "cyl"},
	"vase": {"name": "Vase", "size": Vector3(0.5, 0.68, 0.5), "shape": "cyl"},
	"flower_pot": {"name": "Flower pot", "size": Vector3(0.36, 0.48, 0.36), "shape": "cyl"},
	"potted_plant": {"name": "Potted plant", "size": Vector3(0.5, 0.8, 0.5), "shape": "cyl"},
	# Storage and work
	"crate": {"name": "Crate", "size": Vector3(0.9, 0.9, 0.9), "shape": "box"},
	"small_crate": {"name": "Small crate", "size": Vector3(0.55, 0.55, 0.55), "shape": "box"},
	"barrel": {"name": "Barrel", "size": Vector3(0.84, 1.0, 0.84), "shape": "cyl"},
	"keg": {"name": "Keg", "size": Vector3(0.48, 0.55, 0.48), "shape": "cyl"},
	"bucket": {"name": "Bucket", "size": Vector3(0.46, 0.5, 0.46), "shape": "cyl"},
	"sack": {"name": "Sack", "size": Vector3(0.6, 0.72, 0.6), "shape": "cyl"},
	"basket": {"name": "Basket", "size": Vector3(0.62, 0.56, 0.62), "shape": "cyl"},
	"cauldron": {"name": "Cauldron", "size": Vector3(0.9, 0.72, 0.9), "shape": "cyl"},
	"anvil": {"name": "Anvil", "size": Vector3(0.7, 0.56, 0.35), "shape": "box"},
	"grindstone": {"name": "Grindstone", "size": Vector3(0.8, 0.95, 0.5), "shape": "box"},
	"logs": {"name": "Log pile", "size": Vector3(1.2, 0.65, 0.75), "shape": "box"},
	"firewood": {"name": "Firewood", "size": Vector3(1.0, 0.7, 0.6), "shape": "box"},
	"broom": {"name": "Broom", "size": Vector3(0.3, 1.4, 0.3), "shape": "cyl"},
	"milk_can": {"name": "Milk can", "size": Vector3(0.36, 0.7, 0.36), "shape": "cyl"},
	"watering_can": {"name": "Watering can", "size": Vector3(0.5, 0.36, 0.24), "shape": "box"},
	"wheelbarrow": {"name": "Wheelbarrow", "size": Vector3(0.7, 0.6, 1.4), "shape": "box"},
	"trough": {"name": "Trough", "size": Vector3(1.4, 0.5, 0.6), "shape": "box"},
	"cartwheel": {"name": "Cart wheel", "size": Vector3(1.0, 1.0, 0.25), "shape": "box"},
	# Food and farm
	"pumpkin": {"name": "Pumpkin", "size": Vector3(0.7, 0.6, 0.7), "shape": "cyl"},
	"cabbage": {"name": "Cabbage", "size": Vector3(0.44, 0.38, 0.44), "shape": "cyl"},
	"haybale": {"name": "Hay bale", "size": Vector3(1.2, 0.7, 0.8), "shape": "box"},
	"haystack": {"name": "Haystack", "size": Vector3(1.4, 1.3, 1.4), "shape": "cyl"},
	"chicken": {"name": "Chicken", "size": Vector3(0.36, 0.5, 0.56), "shape": "box"},
	"beehive": {"name": "Beehive", "size": Vector3(0.6, 0.66, 0.6), "shape": "cyl"},
	"scarecrow": {"name": "Scarecrow", "size": Vector3(1.2, 1.9, 0.4), "shape": "box"},
	"sunflower": {"name": "Sunflower", "size": Vector3(0.5, 1.6, 0.5), "shape": "cyl"},
	# Outdoors
	"lantern": {"name": "Lantern post", "size": Vector3(0.32, 1.8, 0.32), "shape": "cyl"},
	"fence": {"name": "Fence", "size": Vector3(1.6, 0.9, 0.15), "shape": "box"},
	"signpost": {"name": "Signpost", "size": Vector3(0.9, 1.8, 0.2), "shape": "box"},
	"mailbox": {"name": "Mailbox", "size": Vector3(0.3, 1.3, 0.4), "shape": "box"},
	"birdhouse": {"name": "Birdhouse", "size": Vector3(0.4, 1.6, 0.4), "shape": "cyl"},
	"gnome": {"name": "Garden gnome", "size": Vector3(0.3, 0.7, 0.3), "shape": "cyl"},
	"stump": {"name": "Tree stump", "size": Vector3(0.8, 0.52, 0.8), "shape": "cyl"},
	"rock": {"name": "Rock", "size": Vector3(1.0, 0.6, 1.0), "shape": "cyl"},
	"small_rock": {"name": "Small rock", "size": Vector3(0.5, 0.3, 0.45), "shape": "cyl"},
	"bush": {"name": "Bush", "size": Vector3(1.2, 0.9, 1.2), "shape": "cyl"},
	"fern": {"name": "Fern", "size": Vector3(0.9, 0.5, 0.9), "shape": "cyl"},
	"mushroom": {"name": "Mushroom", "size": Vector3(0.8, 0.68, 0.8), "shape": "cyl"},
}

## Little things: they go on tables and shelves and are what Clutter sprouts.
const SMALL := [
	"mug", "bottle", "jug", "plates", "bread", "cheese", "kettle", "candle", "cooking_pot",
	"books", "hourglass", "table_lamp", "flower_pot", "globe", "birdcage", "bucket", "cabbage",
	"small_crate", "watering_can", "gnome", "chicken", "small_rock", "keg", "pillow",
]
const TABLETOP := [
	"mug", "bottle", "jug", "plates", "bread", "cheese", "kettle", "candle", "cooking_pot",
	"books", "hourglass", "table_lamp", "flower_pot", "cabbage",
]

static var _meshes := {}


static func display_name(id: String) -> String:
	return PROPS[id].name if PROPS.has(id) else id


static func size_of(id: String) -> Vector3:
	return PROPS[id].size


## Radius and height of the capsule a hider uses while disguised as this prop.
static func capsule_for(id: String) -> Vector2:
	var size: Vector3 = PROPS[id].size
	var radius := maxf(minf(maxf(size.x, size.z) * 0.42, size.y * 0.5), 0.12)
	return Vector2(radius, maxf(size.y, radius * 2.0))


## Bigger props are easier to spot, so they get more health.
static func max_hp_for(id: String) -> int:
	if id == "" or not PROPS.has(id):
		return 100
	var size: Vector3 = PROPS[id].size
	var volume := size.x * size.y * size.z
	return clampi(int(50.0 + volume * 90.0), 50, 150)


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


static func build_visual(id: String) -> Node3D:
	var model := Node3D.new()
	model.name = "Model"
	if not _meshes.has(id):
		var batch := MeshBatch.new()
		_recipe(batch, id)
		_meshes[id] = batch.build()
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[id]
	model.add_child(mi)
	if id == "lantern":
		var light := OmniLight3D.new()
		light.position = Vector3(0, 1.5, 0)
		light.light_color = Color(1.0, 0.8, 0.5)
		light.light_energy = 1.2
		light.omni_range = 5.0
		model.add_child(light)
	return model


# --- Primitive helpers (shared with the map and the player models) -----------

static func box(b: MeshBatch, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO, glow := false) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	b.add(mesh, Transform3D(Basis.from_euler(rot), pos), color, glow)


static func cyl(b: MeshBatch, radius: float, height: float, pos: Vector3, color: Color, top := -1.0, rot := Vector3.ZERO, glow := false) -> void:
	var mesh := CylinderMesh.new()
	mesh.bottom_radius = radius
	mesh.top_radius = radius if top < 0.0 else top
	mesh.height = height
	mesh.radial_segments = 14
	mesh.rings = 1
	b.add(mesh, Transform3D(Basis.from_euler(rot), pos), color, glow)


static func sphere(b: MeshBatch, radius: float, pos: Vector3, color: Color, scale := Vector3.ONE, rot := Vector3.ZERO, glow := false) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 14
	mesh.rings = 7
	b.add(mesh, Transform3D(Basis.from_euler(rot) * Basis.from_scale(scale), pos), color, glow)


static func torus(b: MeshBatch, inner: float, outer: float, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = inner
	mesh.outer_radius = outer
	mesh.rings = 20
	mesh.ring_segments = 6
	b.add(mesh, Transform3D(Basis.from_euler(rot), pos), color)


# --- Recipes -----------------------------------------------------------------

static func _recipe(b: MeshBatch, id: String) -> void:
	var r90 := PI / 2
	match id:
		"chair":
			for x in [-0.2, 0.2]:
				for z in [-0.2, 0.2]:
					box(b, Vector3(0.06, 0.45, 0.06), Vector3(x, 0.225, z), WOOD_DARK)
			box(b, Vector3(0.5, 0.08, 0.5), Vector3(0, 0.47, 0), WOOD)
			box(b, Vector3(0.06, 0.5, 0.06), Vector3(-0.2, 0.75, -0.22), WOOD_DARK)
			box(b, Vector3(0.06, 0.5, 0.06), Vector3(0.2, 0.75, -0.22), WOOD_DARK)
			box(b, Vector3(0.46, 0.22, 0.05), Vector3(0, 0.86, -0.22), WOOD)
		"stool":
			for i in 3:
				var a := i * TAU / 3.0
				box(b, Vector3(0.05, 0.45, 0.05), Vector3(cos(a) * 0.14, 0.225, sin(a) * 0.14), WOOD_DARK)
			cyl(b, 0.22, 0.06, Vector3(0, 0.47, 0), WOOD)
		"table":
			for x in [-0.62, 0.62]:
				for z in [-0.32, 0.32]:
					box(b, Vector3(0.08, 0.72, 0.08), Vector3(x, 0.36, z), WOOD_DARK)
			box(b, Vector3(1.4, 0.08, 0.8), Vector3(0, 0.76, 0), WOOD)
		"round_table":
			cyl(b, 0.3, 0.06, Vector3(0, 0.03, 0), WOOD_DARK, 0.2)
			cyl(b, 0.07, 0.7, Vector3(0, 0.4, 0), WOOD_DARK)
			cyl(b, 0.55, 0.06, Vector3(0, 0.75, 0), WOOD)
		"bench":
			box(b, Vector3(0.07, 0.43, 0.36), Vector3(-0.55, 0.215, 0), WOOD_DARK)
			box(b, Vector3(0.07, 0.43, 0.36), Vector3(0.55, 0.215, 0), WOOD_DARK)
			box(b, Vector3(1.4, 0.07, 0.4), Vector3(0, 0.465, 0), WOOD)
		"armchair":
			var cloth := Color(0.66, 0.26, 0.26)
			box(b, Vector3(0.8, 0.25, 0.75), Vector3(0, 0.125, 0), WOOD_DARK)
			box(b, Vector3(0.6, 0.2, 0.66), Vector3(0, 0.35, 0.05), cloth)
			box(b, Vector3(0.8, 0.62, 0.16), Vector3(0, 0.69, -0.32), cloth)
			box(b, Vector3(0.12, 0.32, 0.75), Vector3(-0.36, 0.53, 0), cloth.darkened(0.15))
			box(b, Vector3(0.12, 0.32, 0.75), Vector3(0.36, 0.53, 0), cloth.darkened(0.15))
		"bookshelf":
			_bookshelf(b)
		"cupboard":
			box(b, Vector3(1.1, 1.0, 0.5), Vector3(0, 0.5, 0), WOOD)
			box(b, Vector3(0.48, 0.8, 0.04), Vector3(-0.26, 0.5, 0.26), WOOD_DARK)
			box(b, Vector3(0.48, 0.8, 0.04), Vector3(0.26, 0.5, 0.26), WOOD_DARK)
			box(b, Vector3(1.0, 0.75, 0.3), Vector3(0, 1.4, -0.1), WOOD_LIGHT)
			box(b, Vector3(1.04, 0.05, 0.34), Vector3(0, 1.8, -0.1), WOOD_DARK)
			for x in [-0.3, 0.0, 0.3]:
				cyl(b, 0.11, 0.03, Vector3(x, 1.45, 0.075), CREAM, -1.0, Vector3(r90, 0, 0))
		"wardrobe":
			box(b, Vector3(1.2, 2.0, 0.6), Vector3(0, 1.0, 0), WOOD_DARK)
			box(b, Vector3(0.56, 1.85, 0.04), Vector3(-0.3, 1.0, 0.31), WOOD)
			box(b, Vector3(0.56, 1.85, 0.04), Vector3(0.3, 1.0, 0.31), WOOD)
			sphere(b, 0.03, Vector3(-0.06, 1.0, 0.35), BRASS)
			sphere(b, 0.03, Vector3(0.06, 1.0, 0.35), BRASS)
			box(b, Vector3(1.28, 0.1, 0.66), Vector3(0, 2.05, 0), WOOD_DARK.darkened(0.2))
		"nightstand":
			box(b, Vector3(0.5, 0.55, 0.45), Vector3(0, 0.275, 0), WOOD)
			box(b, Vector3(0.42, 0.18, 0.04), Vector3(0, 0.38, 0.235), WOOD_DARK)
			sphere(b, 0.025, Vector3(0, 0.38, 0.27), BRASS)
			box(b, Vector3(0.54, 0.05, 0.49), Vector3(0, 0.575, 0), WOOD_DARK)
		"clock":
			box(b, Vector3(0.5, 1.9, 0.3), Vector3(0, 0.95, 0), WOOD_DARK)
			box(b, Vector3(0.55, 0.08, 0.35), Vector3(0, 1.86, 0), WOOD)
			box(b, Vector3(0.24, 0.6, 0.04), Vector3(0, 0.8, 0.16), BRASS)
			cyl(b, 0.18, 0.04, Vector3(0, 1.55, 0.16), CREAM, -1.0, Vector3(r90, 0, 0))
			box(b, Vector3(0.02, 0.13, 0.02), Vector3(0, 1.6, 0.19), IRON)
			box(b, Vector3(0.1, 0.02, 0.02), Vector3(0.04, 1.55, 0.19), IRON)
		"bed":
			box(b, Vector3(1.0, 0.35, 2.0), Vector3(0, 0.175, 0), WOOD)
			box(b, Vector3(0.92, 0.15, 1.85), Vector3(0, 0.42, 0.05), CREAM)
			box(b, Vector3(0.96, 0.1, 1.2), Vector3(0, 0.5, 0.36), Color(0.35, 0.5, 0.8))
			box(b, Vector3(0.6, 0.12, 0.3), Vector3(0, 0.56, -0.72), Color(1, 1, 1))
			box(b, Vector3(1.0, 0.8, 0.08), Vector3(0, 0.4, -0.96), WOOD_DARK)
		"chest":
			box(b, Vector3(0.9, 0.4, 0.55), Vector3(0, 0.2, 0), WOOD)
			cyl(b, 0.27, 0.9, Vector3(0, 0.4, 0), WOOD_DARK, -1.0, Vector3(0, 0, r90))
			for x in [-0.3, 0.3]:
				box(b, Vector3(0.06, 0.42, 0.59), Vector3(x, 0.2, 0), IRON)
				cyl(b, 0.29, 0.06, Vector3(x, 0.4, 0), IRON, -1.0, Vector3(0, 0, r90))
			box(b, Vector3(0.1, 0.12, 0.04), Vector3(0, 0.38, 0.29), BRASS)
		"coat_rack":
			cyl(b, 0.22, 0.06, Vector3(0, 0.03, 0), WOOD_DARK, 0.06)
			cyl(b, 0.03, 1.7, Vector3(0, 0.88, 0), WOOD_DARK)
			cyl(b, 0.17, 0.03, Vector3(0, 1.75, 0), Color(0.45, 0.3, 0.2))
			cyl(b, 0.09, 0.1, Vector3(0, 1.81, 0), Color(0.45, 0.3, 0.2))
			box(b, Vector3(0.3, 0.6, 0.12), Vector3(0, 1.25, 0.1), Color(0.3, 0.5, 0.35))
		"pillow":
			sphere(b, 0.25, Vector3(0, 0.08, 0), Color(0.8, 0.75, 0.9), Vector3(1, 0.32, 0.7))
		"toy_horse":
			box(b, Vector3(0.45, 0.18, 0.16), Vector3(0, 0.36, 0), WOOD_LIGHT)
			box(b, Vector3(0.12, 0.25, 0.12), Vector3(0.25, 0.5, 0), WOOD_LIGHT, Vector3(0, 0, -0.3))
			for x in [-0.17, 0.17]:
				for z in [-0.06, 0.06]:
					box(b, Vector3(0.05, 0.24, 0.05), Vector3(x, 0.18, z), WOOD_DARK)
			box(b, Vector3(0.6, 0.04, 0.04), Vector3(0, 0.04, -0.06), WOOD_DARK)
			box(b, Vector3(0.6, 0.04, 0.04), Vector3(0, 0.04, 0.06), WOOD_DARK)
			box(b, Vector3(0.04, 0.16, 0.04), Vector3(0.3, 0.6, 0), Color(0.3, 0.2, 0.1))
		"mug":
			cyl(b, 0.07, 0.14, Vector3(0, 0.07, 0), Color(0.55, 0.38, 0.22))
			box(b, Vector3(0.04, 0.08, 0.04), Vector3(0.09, 0.075, 0), Color(0.45, 0.3, 0.18))
			cyl(b, 0.065, 0.03, Vector3(0, 0.145, 0), CREAM)
		"bottle":
			cyl(b, 0.06, 0.22, Vector3(0, 0.11, 0), Color(0.2, 0.45, 0.25))
			cyl(b, 0.025, 0.1, Vector3(0, 0.27, 0), Color(0.2, 0.45, 0.25))
			cyl(b, 0.03, 0.04, Vector3(0, 0.34, 0), WOOD)
		"jug":
			sphere(b, 0.15, Vector3(0, 0.15, 0), Color(0.75, 0.6, 0.45))
			cyl(b, 0.08, 0.14, Vector3(0, 0.33, 0), Color(0.75, 0.6, 0.45), 0.1)
			box(b, Vector3(0.04, 0.18, 0.05), Vector3(0.16, 0.25, 0), Color(0.65, 0.5, 0.38))
		"plates":
			for i in 4:
				cyl(b, 0.16, 0.025, Vector3(0, 0.0125 + i * 0.03, 0), CREAM, 0.14)
		"bread":
			sphere(b, 0.18, Vector3(0, 0.08, 0), Color(0.82, 0.58, 0.3), Vector3(1, 0.45, 0.55))
		"cheese":
			cyl(b, 0.22, 0.2, Vector3(0, 0.1, 0), Color(0.98, 0.82, 0.35))
			cyl(b, 0.23, 0.03, Vector3(0, 0.19, 0), Color(0.9, 0.68, 0.28))
		"kettle":
			sphere(b, 0.15, Vector3(0, 0.14, 0), Color(0.75, 0.45, 0.25), Vector3(1, 0.85, 1))
			cyl(b, 0.03, 0.16, Vector3(0.17, 0.17, 0), Color(0.75, 0.45, 0.25), 0.015, Vector3(0, 0, -0.9))
			sphere(b, 0.03, Vector3(0, 0.28, 0), IRON)
			box(b, Vector3(0.04, 0.04, 0.22), Vector3(0, 0.31, 0), IRON)
		"candle":
			cyl(b, 0.06, 0.02, Vector3(0, 0.01, 0), BRASS)
			cyl(b, 0.035, 0.2, Vector3(0, 0.12, 0), CREAM)
			sphere(b, 0.025, Vector3(0, 0.25, 0), Color(1.0, 0.7, 0.25), Vector3(1, 1.6, 1), Vector3.ZERO, true)
		"cooking_pot":
			cyl(b, 0.2, 0.26, Vector3(0, 0.13, 0), IRON, 0.21)
			cyl(b, 0.22, 0.03, Vector3(0, 0.26, 0), IRON.lightened(0.15))
			box(b, Vector3(0.06, 0.03, 0.04), Vector3(-0.24, 0.22, 0), IRON)
			box(b, Vector3(0.06, 0.03, 0.04), Vector3(0.24, 0.22, 0), IRON)
		"books":
			box(b, Vector3(0.32, 0.07, 0.24), Vector3(0, 0.035, 0), BOOKS[0])
			box(b, Vector3(0.3, 0.06, 0.22), Vector3(0, 0.1, 0), BOOKS[1], Vector3(0, 0.2, 0))
			box(b, Vector3(0.33, 0.08, 0.23), Vector3(0, 0.17, 0), BOOKS[2], Vector3(0, -0.15, 0))
			box(b, Vector3(0.28, 0.06, 0.2), Vector3(0, 0.24, 0), BOOKS[3])
		"globe":
			cyl(b, 0.14, 0.05, Vector3(0, 0.025, 0), WOOD_DARK, 0.1)
			cyl(b, 0.02, 0.2, Vector3(0, 0.14, 0), WOOD_DARK)
			sphere(b, 0.17, Vector3(0, 0.4, 0), Color(0.3, 0.55, 0.8))
			sphere(b, 0.08, Vector3(0.1, 0.46, 0.09), LEAF, Vector3(1, 0.7, 0.7))
			sphere(b, 0.07, Vector3(-0.11, 0.35, -0.08), LEAF, Vector3(1, 0.8, 0.7))
			torus(b, 0.18, 0.2, Vector3(0, 0.4, 0), BRASS, Vector3(0, 0, 0.4))
		"birdcage":
			cyl(b, 0.17, 0.04, Vector3(0, 0.02, 0), BRASS)
			for i in 8:
				var a := i * TAU / 8.0
				cyl(b, 0.008, 0.4, Vector3(cos(a) * 0.16, 0.24, sin(a) * 0.16), BRASS)
			sphere(b, 0.17, Vector3(0, 0.44, 0), BRASS, Vector3(1, 0.6, 1))
			cyl(b, 0.012, 0.1, Vector3(0, 0.57, 0), BRASS)
			sphere(b, 0.05, Vector3(0, 0.12, 0), Color(1.0, 0.85, 0.2))
		"hourglass":
			cyl(b, 0.1, 0.03, Vector3(0, 0.015, 0), WOOD_DARK)
			cyl(b, 0.1, 0.03, Vector3(0, 0.305, 0), WOOD_DARK)
			cyl(b, 0.08, 0.13, Vector3(0, 0.095, 0), Color(0.75, 0.85, 0.95), 0.012)
			cyl(b, 0.012, 0.13, Vector3(0, 0.225, 0), Color(0.75, 0.85, 0.95), 0.08)
			cyl(b, 0.06, 0.05, Vector3(0, 0.055, 0), STRAW, 0.0)
			for i in 3:
				var a := i * TAU / 3.0
				cyl(b, 0.012, 0.28, Vector3(cos(a) * 0.085, 0.16, sin(a) * 0.085), WOOD_DARK)
		"table_lamp":
			cyl(b, 0.12, 0.04, Vector3(0, 0.02, 0), BRASS)
			cyl(b, 0.02, 0.25, Vector3(0, 0.165, 0), BRASS)
			cyl(b, 0.15, 0.18, Vector3(0, 0.37, 0), Color(1.0, 0.9, 0.65), 0.08, Vector3.ZERO, true)
		"vase":
			sphere(b, 0.25, Vector3(0, 0.26, 0), TERRACOTTA)
			cyl(b, 0.1, 0.2, Vector3(0, 0.55, 0), TERRACOTTA, 0.14)
			cyl(b, 0.16, 0.04, Vector3(0, 0.66, 0), TERRACOTTA.darkened(0.15))
		"flower_pot":
			cyl(b, 0.13, 0.24, Vector3(0, 0.12, 0), TERRACOTTA, 0.17)
			var petals := [Color(0.95, 0.45, 0.65), Color(1.0, 0.85, 0.25), Color(0.6, 0.4, 0.9)]
			for i in 3:
				var a := i * TAU / 3.0
				var p := Vector3(cos(a) * 0.07, 0, sin(a) * 0.07)
				cyl(b, 0.012, 0.2, p + Vector3(0, 0.33, 0), LEAF)
				sphere(b, 0.06, p + Vector3(0, 0.44, 0), petals[i])
		"potted_plant":
			cyl(b, 0.16, 0.3, Vector3(0, 0.15, 0), TERRACOTTA, 0.2)
			sphere(b, 0.22, Vector3(0, 0.48, 0), LEAF)
			sphere(b, 0.16, Vector3(0.12, 0.62, 0.05), LEAF.lightened(0.1))
			sphere(b, 0.15, Vector3(-0.1, 0.64, -0.06), LEAF.darkened(0.1))
		"crate":
			_crate(b, 0.9)
		"small_crate":
			_crate(b, 0.55)
		"barrel":
			_barrel(b, 1.0)
		"keg":
			_barrel(b, 0.55)
		"bucket":
			cyl(b, 0.18, 0.36, Vector3(0, 0.18, 0), Color(0.56, 0.6, 0.64), 0.23)
			cyl(b, 0.23, 0.04, Vector3(0, 0.3, 0), IRON)
			box(b, Vector3(0.03, 0.15, 0.03), Vector3(-0.22, 0.43, 0), IRON)
			box(b, Vector3(0.03, 0.15, 0.03), Vector3(0.22, 0.43, 0), IRON)
			box(b, Vector3(0.47, 0.03, 0.03), Vector3(0, 0.5, 0), IRON)
		"sack":
			sphere(b, 0.3, Vector3(0, 0.31, 0), BURLAP, Vector3(1, 1.05, 0.88))
			cyl(b, 0.09, 0.04, Vector3(0, 0.62, 0), WOOD_DARK)
			cyl(b, 0.07, 0.12, Vector3(0, 0.67, 0), BURLAP, 0.13)
		"basket":
			cyl(b, 0.25, 0.3, Vector3(0, 0.15, 0), Color(0.72, 0.55, 0.3), 0.3)
			cyl(b, 0.31, 0.04, Vector3(0, 0.3, 0), Color(0.55, 0.4, 0.2))
			box(b, Vector3(0.04, 0.24, 0.04), Vector3(0, 0.42, -0.27), Color(0.55, 0.4, 0.2))
			box(b, Vector3(0.04, 0.24, 0.04), Vector3(0, 0.42, 0.27), Color(0.55, 0.4, 0.2))
			box(b, Vector3(0.04, 0.04, 0.58), Vector3(0, 0.54, 0), Color(0.55, 0.4, 0.2))
			for apple in [Vector3(0.08, 0.31, 0.05), Vector3(-0.08, 0.32, -0.04), Vector3(0.0, 0.33, 0.12)]:
				sphere(b, 0.07, apple, Color(0.85, 0.15, 0.15))
		"cauldron":
			sphere(b, 0.45, Vector3(0, 0.38, 0), IRON, Vector3(1, 0.75, 1))
			cyl(b, 0.32, 0.06, Vector3(0, 0.64, 0), IRON.lightened(0.1))
			cyl(b, 0.29, 0.02, Vector3(0, 0.68, 0), Color(0.4, 0.9, 0.3), -1.0, Vector3.ZERO, true)
			for i in 3:
				var a := i * TAU / 3.0
				cyl(b, 0.05, 0.12, Vector3(cos(a) * 0.25, 0.06, sin(a) * 0.25), IRON)
		"anvil":
			box(b, Vector3(0.35, 0.22, 0.26), Vector3(0, 0.11, 0), IRON)
			box(b, Vector3(0.2, 0.16, 0.18), Vector3(0, 0.3, 0), IRON)
			box(b, Vector3(0.5, 0.16, 0.3), Vector3(-0.05, 0.46, 0), IRON.lightened(0.1))
			cyl(b, 0.08, 0.2, Vector3(0.3, 0.47, 0), IRON.lightened(0.1), 0.02, Vector3(0, 0, -r90))
		"grindstone":
			box(b, Vector3(0.08, 0.7, 0.08), Vector3(-0.3, 0.35, 0), WOOD_DARK)
			box(b, Vector3(0.08, 0.7, 0.08), Vector3(0.3, 0.35, 0), WOOD_DARK)
			cyl(b, 0.38, 0.14, Vector3(0, 0.56, 0), STONE, -1.0, Vector3(0, 0, r90))
			cyl(b, 0.03, 0.72, Vector3(0, 0.56, 0), IRON, -1.0, Vector3(0, 0, r90))
			box(b, Vector3(0.05, 0.2, 0.05), Vector3(0.38, 0.48, 0), IRON)
		"logs":
			for pos in [Vector3(0, 0.17, -0.19), Vector3(0, 0.17, 0.19), Vector3(0, 0.47, 0)]:
				cyl(b, 0.17, 1.2, pos, WOOD_DARK, -1.0, Vector3(0, 0, r90))
				cyl(b, 0.14, 1.24, pos, WOOD_LIGHT, -1.0, Vector3(0, 0, r90))
		"firewood":
			for row in 3:
				for z in ([-0.2, 0.0, 0.2] if row < 2 else [-0.1, 0.1]):
					var pos := Vector3(0, 0.1 + row * 0.19, z)
					cyl(b, 0.09, 1.0, pos, WOOD_DARK, -1.0, Vector3(0, 0, r90))
					cyl(b, 0.07, 1.04, pos, WOOD_LIGHT, -1.0, Vector3(0, 0, r90))
		"broom":
			cyl(b, 0.14, 0.35, Vector3(0, 0.175, 0), STRAW, 0.05)
			cyl(b, 0.055, 0.04, Vector3(0, 0.36, 0), Color(0.7, 0.2, 0.2))
			cyl(b, 0.022, 1.05, Vector3(0, 0.875, 0), WOOD)
		"milk_can":
			var steel := Color(0.75, 0.77, 0.8)
			cyl(b, 0.17, 0.45, Vector3(0, 0.225, 0), steel)
			cyl(b, 0.17, 0.12, Vector3(0, 0.51, 0), steel, 0.09)
			cyl(b, 0.09, 0.08, Vector3(0, 0.61, 0), steel)
			cyl(b, 0.11, 0.04, Vector3(0, 0.67, 0), steel.darkened(0.2))
		"watering_can":
			var tin := Color(0.45, 0.6, 0.5)
			cyl(b, 0.11, 0.22, Vector3(0, 0.11, 0), tin)
			cyl(b, 0.02, 0.28, Vector3(0.17, 0.2, 0), tin, 0.035, Vector3(0, 0, -1.0))
			box(b, Vector3(0.2, 0.03, 0.03), Vector3(-0.02, 0.32, 0), tin.darkened(0.2))
		"wheelbarrow":
			box(b, Vector3(0.6, 0.25, 0.8), Vector3(0, 0.45, 0.15), WOOD)
			cyl(b, 0.2, 0.08, Vector3(0, 0.2, 0.6), WOOD_DARK, -1.0, Vector3(0, 0, r90))
			box(b, Vector3(0.04, 0.04, 0.6), Vector3(-0.22, 0.45, -0.5), WOOD_DARK)
			box(b, Vector3(0.04, 0.04, 0.6), Vector3(0.22, 0.45, -0.5), WOOD_DARK)
			box(b, Vector3(0.04, 0.3, 0.04), Vector3(-0.22, 0.15, -0.15), WOOD_DARK)
			box(b, Vector3(0.04, 0.3, 0.04), Vector3(0.22, 0.15, -0.15), WOOD_DARK)
		"trough":
			box(b, Vector3(1.4, 0.4, 0.6), Vector3(0, 0.25, 0), WOOD)
			box(b, Vector3(1.3, 0.04, 0.5), Vector3(0, 0.47, 0), Color(0.35, 0.6, 0.8))
			box(b, Vector3(0.1, 0.05, 0.6), Vector3(-0.6, 0.025, 0), WOOD_DARK)
			box(b, Vector3(0.1, 0.05, 0.6), Vector3(0.6, 0.025, 0), WOOD_DARK)
		"cartwheel":
			torus(b, 0.42, 0.5, Vector3(0, 0.5, 0), WOOD_DARK, Vector3(r90, 0, 0))
			cyl(b, 0.08, 0.2, Vector3(0, 0.5, 0), IRON, -1.0, Vector3(r90, 0, 0))
			for i in 6:
				box(b, Vector3(0.04, 0.84, 0.04), Vector3(0, 0.5, 0), WOOD, Vector3(0, 0, i * PI / 6.0))
		"pumpkin":
			sphere(b, 0.35, Vector3(0, 0.26, 0), Color(0.95, 0.52, 0.12), Vector3(1, 0.72, 1))
			sphere(b, 0.3, Vector3(0, 0.26, 0), Color(0.88, 0.45, 0.1), Vector3(1.22, 0.76, 0.7))
			cyl(b, 0.04, 0.14, Vector3(0, 0.56, 0), Color(0.3, 0.45, 0.15))
		"cabbage":
			sphere(b, 0.22, Vector3(0, 0.14, 0), LEAF, Vector3(1.0, 0.65, 1.0))
			sphere(b, 0.19, Vector3(0, 0.2, 0), Color(0.6, 0.85, 0.45))
		"haybale":
			box(b, Vector3(1.2, 0.7, 0.8), Vector3(0, 0.35, 0), STRAW)
			box(b, Vector3(0.04, 0.74, 0.84), Vector3(-0.3, 0.35, 0), Color(0.6, 0.45, 0.25))
			box(b, Vector3(0.04, 0.74, 0.84), Vector3(0.3, 0.35, 0), Color(0.6, 0.45, 0.25))
		"haystack":
			cyl(b, 0.7, 0.9, Vector3(0, 0.45, 0), STRAW, 0.35)
			sphere(b, 0.38, Vector3(0, 0.98, 0), STRAW.lightened(0.1), Vector3(1, 0.8, 1))
		"chicken":
			sphere(b, 0.17, Vector3(0, 0.24, 0), Color(0.97, 0.95, 0.9), Vector3(1, 0.9, 1.3))
			sphere(b, 0.08, Vector3(0, 0.4, 0.17), Color(0.97, 0.95, 0.9))
			box(b, Vector3(0.03, 0.07, 0.08), Vector3(0, 0.49, 0.16), Color(0.85, 0.15, 0.15))
			cyl(b, 0.025, 0.07, Vector3(0, 0.39, 0.27), Color(1.0, 0.6, 0.15), 0.0, Vector3(r90, 0, 0))
			sphere(b, 0.09, Vector3(0, 0.32, -0.2), Color(0.9, 0.88, 0.82), Vector3(0.5, 1, 1))
			cyl(b, 0.015, 0.1, Vector3(-0.05, 0.05, 0), Color(1.0, 0.6, 0.15))
			cyl(b, 0.015, 0.1, Vector3(0.05, 0.05, 0), Color(1.0, 0.6, 0.15))
		"beehive":
			for i in 5:
				var radius: float = [0.3, 0.28, 0.24, 0.18, 0.1][i]
				cyl(b, radius, 0.14, Vector3(0, 0.07 + i * 0.13, 0), STRAW if i % 2 == 0 else STRAW.darkened(0.12))
			box(b, Vector3(0.1, 0.08, 0.04), Vector3(0, 0.07, 0.3), WOOD_DARK)
		"scarecrow":
			cyl(b, 0.05, 1.8, Vector3(0, 0.9, 0), WOOD_DARK)
			box(b, Vector3(1.0, 0.06, 0.06), Vector3(0, 1.35, 0), WOOD_DARK)
			box(b, Vector3(0.45, 0.55, 0.22), Vector3(0, 1.2, 0), Color(0.55, 0.35, 0.6))
			sphere(b, 0.17, Vector3(0, 1.62, 0), BURLAP)
			cyl(b, 0.22, 0.03, Vector3(0, 1.76, 0), STRAW)
			cyl(b, 0.12, 0.14, Vector3(0, 1.84, 0), STRAW)
			sphere(b, 0.08, Vector3(-0.53, 1.35, 0), STRAW)
			sphere(b, 0.08, Vector3(0.53, 1.35, 0), STRAW)
		"sunflower":
			cyl(b, 0.03, 1.4, Vector3(0, 0.7, 0), LEAF)
			sphere(b, 0.12, Vector3(0.1, 0.7, 0), LEAF, Vector3(1, 0.3, 0.6), Vector3(0, 0, 0.4))
			sphere(b, 0.12, Vector3(-0.1, 0.95, 0), LEAF, Vector3(1, 0.3, 0.6), Vector3(0, 0, -0.4))
			cyl(b, 0.22, 0.06, Vector3(0, 1.45, 0.03), Color(1.0, 0.82, 0.15), -1.0, Vector3(r90, 0, 0))
			cyl(b, 0.1, 0.06, Vector3(0, 1.45, 0.07), Color(0.4, 0.25, 0.1), -1.0, Vector3(r90, 0, 0))
		"lantern":
			cyl(b, 0.14, 0.08, Vector3(0, 0.04, 0), IRON)
			cyl(b, 0.045, 1.4, Vector3(0, 0.74, 0), IRON)
			box(b, Vector3(0.2, 0.25, 0.2), Vector3(0, 1.56, 0), Color(1.0, 0.85, 0.45), Vector3.ZERO, true)
			cyl(b, 0.16, 0.12, Vector3(0, 1.74, 0), IRON, 0.02)
		"fence":
			box(b, Vector3(0.1, 0.9, 0.1), Vector3(-0.75, 0.45, 0), WOOD_DARK)
			box(b, Vector3(0.1, 0.9, 0.1), Vector3(0.75, 0.45, 0), WOOD_DARK)
			box(b, Vector3(1.5, 0.08, 0.05), Vector3(0, 0.3, 0.06), WOOD)
			box(b, Vector3(1.5, 0.08, 0.05), Vector3(0, 0.7, 0.06), WOOD)
		"signpost":
			cyl(b, 0.05, 1.8, Vector3(0, 0.9, 0), WOOD_DARK)
			box(b, Vector3(0.8, 0.18, 0.04), Vector3(0.15, 1.5, 0.07), WOOD_LIGHT, Vector3(0, 0.1, 0))
			box(b, Vector3(0.7, 0.16, 0.04), Vector3(-0.1, 1.25, 0.07), WOOD_LIGHT, Vector3(0, -0.15, 0))
		"mailbox":
			box(b, Vector3(0.08, 1.0, 0.08), Vector3(0, 0.5, 0), WOOD_DARK)
			box(b, Vector3(0.25, 0.2, 0.36), Vector3(0, 1.08, 0), Color(0.75, 0.2, 0.2))
			cyl(b, 0.125, 0.36, Vector3(0, 1.18, 0), Color(0.75, 0.2, 0.2), -1.0, Vector3(r90, 0, 0))
			box(b, Vector3(0.03, 0.16, 0.04), Vector3(0.145, 1.22, 0.06), Color(1.0, 0.8, 0.2))
		"birdhouse":
			cyl(b, 0.04, 1.2, Vector3(0, 0.6, 0), WOOD_DARK)
			box(b, Vector3(0.3, 0.3, 0.3), Vector3(0, 1.35, 0), WOOD_LIGHT)
			box(b, Vector3(0.38, 0.03, 0.24), Vector3(0, 1.55, 0.08), Color(0.75, 0.25, 0.2), Vector3(0.6, 0, 0))
			box(b, Vector3(0.38, 0.03, 0.24), Vector3(0, 1.55, -0.08), Color(0.75, 0.25, 0.2), Vector3(-0.6, 0, 0))
			cyl(b, 0.05, 0.02, Vector3(0, 1.38, 0.155), WOOD_DARK.darkened(0.4), -1.0, Vector3(r90, 0, 0))
		"gnome":
			cyl(b, 0.14, 0.28, Vector3(0, 0.14, 0), Color(0.25, 0.4, 0.75), 0.1)
			sphere(b, 0.1, Vector3(0, 0.33, 0.07), Color(0.97, 0.97, 0.97), Vector3(1, 1.2, 0.6))
			sphere(b, 0.08, Vector3(0, 0.39, 0.02), Color(0.96, 0.8, 0.66))
			sphere(b, 0.03, Vector3(0, 0.38, 0.11), Color(0.95, 0.6, 0.55))
			cyl(b, 0.12, 0.28, Vector3(0, 0.56, 0), Color(0.85, 0.2, 0.2), 0.0)
		"stump":
			cyl(b, 0.4, 0.5, Vector3(0, 0.25, 0), Color(0.45, 0.3, 0.18), 0.34)
			cyl(b, 0.31, 0.03, Vector3(0, 0.505, 0), WOOD_LIGHT)
			for i in 3:
				var a := i * TAU / 3.0 + 0.4
				box(b, Vector3(0.32, 0.12, 0.12), Vector3(cos(a) * 0.38, 0.06, sin(a) * 0.38), Color(0.45, 0.3, 0.18), Vector3(0, -a, 0))
		"rock":
			sphere(b, 0.5, Vector3(0, 0.28, 0), STONE, Vector3(1.0, 0.6, 0.85))
			sphere(b, 0.26, Vector3(0.3, 0.16, 0.22), STONE.darkened(0.15))
		"small_rock":
			sphere(b, 0.22, Vector3(0, 0.13, 0), STONE.darkened(0.05), Vector3(1, 0.65, 0.9))
			sphere(b, 0.12, Vector3(0.15, 0.08, 0.1), STONE.lightened(0.05))
		"bush":
			sphere(b, 0.45, Vector3(0, 0.45, 0), LEAF)
			sphere(b, 0.35, Vector3(0.32, 0.35, 0.15), LEAF.lightened(0.1))
			sphere(b, 0.35, Vector3(-0.3, 0.38, -0.15), LEAF.darkened(0.1))
			sphere(b, 0.28, Vector3(0.05, 0.58, -0.25), LEAF.lightened(0.05))
		"fern":
			for i in 7:
				var a := i * TAU / 7.0
				sphere(b, 0.3, Vector3(sin(a) * 0.2, 0.25, cos(a) * 0.2), LEAF.darkened(0.05 * (i % 3)), Vector3(0.28, 0.1, 1), Vector3(-0.5, a, 0))
		"mushroom":
			cyl(b, 0.13, 0.42, Vector3(0, 0.21, 0), CREAM, 0.1)
			sphere(b, 0.4, Vector3(0, 0.46, 0), Color(0.86, 0.2, 0.18), Vector3(1, 0.55, 1))
			for dot in [Vector3(0.15, 0.65, 0.1), Vector3(-0.18, 0.63, -0.05), Vector3(0.02, 0.67, -0.17), Vector3(-0.06, 0.62, 0.24), Vector3(0.27, 0.57, -0.12)]:
				sphere(b, 0.055, dot, Color(1, 1, 1))
		_:
			box(b, Vector3(0.5, 0.5, 0.5), Vector3(0, 0.25, 0), Color(1, 0, 1))


static func _crate(b: MeshBatch, s: float) -> void:
	box(b, Vector3(s, s, s), Vector3(0, s * 0.5, 0), WOOD)
	var band := Vector3(s + 0.04, s * 0.11, s + 0.04)
	box(b, band, Vector3(0, s * 0.08, 0), WOOD_DARK)
	box(b, band, Vector3(0, s * 0.92, 0), WOOD_DARK)
	var diagonal := s * 1.2
	var off := s * 0.5 + 0.02
	box(b, Vector3(diagonal, s * 0.1, 0.03), Vector3(0, s * 0.5, off), WOOD_DARK, Vector3(0, 0, PI / 4))
	box(b, Vector3(diagonal, s * 0.1, 0.03), Vector3(0, s * 0.5, -off), WOOD_DARK, Vector3(0, 0, -PI / 4))
	box(b, Vector3(0.03, s * 0.1, diagonal), Vector3(off, s * 0.5, 0), WOOD_DARK, Vector3(PI / 4, 0, 0))
	box(b, Vector3(0.03, s * 0.1, diagonal), Vector3(-off, s * 0.5, 0), WOOD_DARK, Vector3(-PI / 4, 0, 0))


static func _barrel(b: MeshBatch, s: float) -> void:
	cyl(b, 0.34 * s, 0.5 * s, Vector3(0, 0.25 * s, 0), WOOD, 0.4 * s)
	cyl(b, 0.4 * s, 0.5 * s, Vector3(0, 0.75 * s, 0), WOOD, 0.34 * s)
	cyl(b, 0.33 * s, 0.03, Vector3(0, s, 0), WOOD_DARK)
	for band in [[0.12, 0.37], [0.5, 0.42], [0.88, 0.37]]:
		cyl(b, band[1] * s + 0.02, 0.06 * s, Vector3(0, band[0] * s, 0), IRON)


static func _bookshelf(b: MeshBatch) -> void:
	box(b, Vector3(1.2, 2.0, 0.04), Vector3(0, 1.0, -0.18), WOOD_DARK)
	box(b, Vector3(0.06, 2.0, 0.4), Vector3(-0.57, 1.0, 0), WOOD)
	box(b, Vector3(0.06, 2.0, 0.4), Vector3(0.57, 1.0, 0), WOOD)
	box(b, Vector3(1.2, 0.06, 0.4), Vector3(0, 1.97, 0), WOOD)
	var book := 0
	for shelf in 4:
		var y := 0.05 + shelf * 0.48
		box(b, Vector3(1.08, 0.05, 0.38), Vector3(0, y, 0), WOOD)
		var x := -0.5
		var end := 0.48 if shelf % 2 == 0 else 0.15
		while x < end:
			var w := 0.07 + 0.025 * ((book * 7) % 3)
			var h := 0.28 + 0.05 * ((book + shelf) % 3)
			box(b, Vector3(w - 0.01, h, 0.3), Vector3(x + w * 0.5, y + 0.025 + h * 0.5, 0.0), BOOKS[book % BOOKS.size()])
			x += w
			book += 1
