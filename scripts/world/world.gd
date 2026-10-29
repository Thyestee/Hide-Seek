extends Node3D
## The playable world: lighting, the village map, players, decoys, projectiles
## and spell effects. On the host it also bakes a navigation mesh for bots.

signal navigation_ready

const MapBuilder = preload("res://scripts/world/map_builder.gd")
const PropLib = preload("res://scripts/world/prop_library.gd")
const PlayerScript = preload("res://scripts/player/player.gd")

var players_root: Node3D
var decoys_root: Node3D
var fx_root: Node3D
var hider_spawns: Array[Vector3] = []
var seeker_spawns: Array[Vector3] = []
var map_props: Array[StaticBody3D] = []
var nav_ready := false

var _bolts := {}   # id -> {node, velocity, life}
var _traps := {}   # id -> node


func _ready() -> void:
	_build_environment()
	var map_parent: Node3D = self
	var region: NavigationRegion3D
	if Net.is_host():
		# Bots need a navigation mesh; only the host runs them.
		region = NavigationRegion3D.new()
		region.name = "Navigation"
		add_child(region)
		map_parent = region
	var builder := MapBuilder.new()
	builder.build(map_parent)
	hider_spawns = builder.hider_spawns
	seeker_spawns = builder.seeker_spawns
	map_props = builder.props
	players_root = _child("Players")
	decoys_root = _child("Decoys")
	fx_root = _child("Fx")
	if region:
		_bake_navigation(region)


func _child(child_name: String) -> Node3D:
	var n := Node3D.new()
	n.name = child_name
	add_child(n)
	return n


func _bake_navigation(region: NavigationRegion3D) -> void:
	var nav := NavigationMesh.new()
	nav.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav.geometry_collision_mask = 1
	nav.cell_size = 0.25
	nav.cell_height = 0.25
	nav.agent_radius = 0.5
	nav.agent_height = 1.75
	nav.agent_max_climb = 0.5
	nav.agent_max_slope = 30.0  # keeps roofs out of the mesh
	nav.filter_baking_aabb = AABB(Vector3(-40, -1, -40), Vector3(80, 6, 80))
	region.navigation_mesh = nav
	region.bake_finished.connect(func():
		nav_ready = true
		navigation_ready.emit()
	)
	region.bake_navigation_mesh(true)


func _build_environment() -> void:
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.32, 0.55, 0.9)
	sky_material.sky_horizon_color = Color(0.75, 0.85, 0.95)
	sky_material.ground_horizon_color = Color(0.75, 0.85, 0.95)
	sky_material.ground_bottom_color = Color(0.35, 0.45, 0.3)
	var sky := Sky.new()
	sky.sky_material = sky_material
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_intensity = 1.5
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.85, 0.95)
	env.fog_density = 0.004
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.15
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.shadow_bias = 0.05
	sun.shadow_normal_bias = 1.5
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


func _physics_process(delta: float) -> void:
	for id in _bolts.keys():
		var bolt: Dictionary = _bolts[id]
		bolt.life -= delta
		if bolt.life <= 0.0:
			end_bolt(id, Vector3.ZERO, false)
			continue
		bolt.velocity += Vector3.DOWN * bolt.gravity * delta
		var node: Node3D = bolt.node
		node.global_position += bolt.velocity * delta


# --- Players -----------------------------------------------------------------

func spawn_player(id: int, role: String, pos: Vector3) -> Node:
	var p := PlayerScript.new()
	p.name = str(id)
	var is_bot := Net.is_bot(id)
	p.setup(id, Net.get_player_name(id), Net.get_player_color(id), id == multiplayer.get_unique_id(), is_bot and Net.is_host())
	players_root.add_child(p)
	p.place_at(pos)
	p.set_role(role)
	return p


func get_player(id: int) -> Node:
	return players_root.get_node_or_null(str(id))


func get_players() -> Array:
	return players_root.get_children()


func remove_player(id: int) -> void:
	var p := get_player(id)
	if p:
		players_root.remove_child(p)
		p.queue_free()


func clear_players() -> void:
	for p in players_root.get_children():
		players_root.remove_child(p)
		p.queue_free()


# --- Decoys ------------------------------------------------------------------

func spawn_decoy(id: int, prop: String, pos: Vector3, yaw: float) -> Node:
	var decoy := PropLib.make_static_prop(prop)
	decoy.name = "Decoy%d" % id
	decoy.set_meta("decoy_id", id)
	decoy.position = pos
	decoy.rotation.y = yaw
	decoys_root.add_child(decoy)
	return decoy


## Removes a decoy and returns where it stood, or null if it was already gone.
func remove_decoy(id: int) -> Variant:
	var decoy := decoys_root.get_node_or_null("Decoy%d" % id) as Node3D
	if decoy == null:
		return null
	var pos := decoy.global_position
	decoys_root.remove_child(decoy)
	decoy.queue_free()
	return pos


func clear_round_objects() -> void:
	for root in [decoys_root, fx_root]:
		for d in root.get_children():
			root.remove_child(d)
			d.queue_free()
	_bolts.clear()
	_traps.clear()


# --- Projectiles (visual only; the host decides what they hit) ---------------

func spawn_bolt(id: int, origin: Vector3, velocity: Vector3, kind: String, gravity: float, life: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 0.12 if kind == "bolt" else 0.16
	mesh.height = mesh.radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.9, 1.0) if kind == "bolt" else Color(1.0, 0.45, 0.2)
	mesh.material = mat
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if kind == "flare":
		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.2)
		light.omni_range = 4.0
		node.add_child(light)
	fx_root.add_child(node)
	node.global_position = origin
	_bolts[id] = {"node": node, "velocity": velocity, "gravity": gravity, "life": life}


func end_bolt(id: int, pos: Vector3, burst: bool) -> void:
	var bolt: Dictionary = _bolts.get(id, {})
	if bolt.is_empty():
		return
	_bolts.erase(id)
	var node: Node3D = bolt.node
	if burst:
		puff(pos, Color(0.6, 0.9, 1.0), 10)
	node.queue_free()


# --- Spell effects -----------------------------------------------------------

func puff(pos: Vector3, color: Color, amount := 24) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = amount
	particles.lifetime = 0.8
	particles.explosiveness = 1.0
	particles.mesh = _ball_mesh(0.1, color.lightened(0.4), 1.0)
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 4.5
	particles.gravity = Vector3(0, -3, 0)
	particles.damping_min = 3.0
	particles.damping_max = 5.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.6
	_add_timed(particles, pos, 1.5)
	particles.emitting = true


## A cloud of big grey puffs that hides whatever is inside it.
func smoke(pos: Vector3, duration: float) -> void:
	var particles := CPUParticles3D.new()
	particles.amount = 70
	particles.lifetime = 2.5
	particles.preprocess = 2.0
	particles.mesh = _ball_mesh(1.0, Color(0.82, 0.84, 0.86), 0.85)
	particles.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	particles.emission_sphere_radius = 3.0
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 0.1
	particles.initial_velocity_max = 0.5
	particles.gravity = Vector3(0, 0.15, 0)
	particles.scale_amount_min = 0.9
	particles.scale_amount_max = 1.8
	_add_timed(particles, pos + Vector3.UP * 1.2, duration + 2.5)
	particles.emitting = true
	get_tree().create_timer(duration).timeout.connect(func():
		if is_instance_valid(particles):
			particles.emitting = false
	)


## An expanding see-through bubble (sonar, shockwave, flare burst).
func wave(pos: Vector3, radius: float, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	var node := MeshInstance3D.new()
	node.mesh = sphere
	node.material_override = mat
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_add_timed(node, pos, 1.0)
	node.scale = Vector3.ONE * 0.5
	var tween := node.create_tween().set_parallel()
	tween.tween_property(node, "scale", Vector3.ONE * radius, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.8)


func flash_light(pos: Vector3, color: Color, radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 4.0
	light.omni_range = radius
	_add_timed(light, pos + Vector3.UP, 0.8)
	light.create_tween().tween_property(light, "light_energy", 0.0, 0.7)


## Snares are only drawn for seekers; hiders can't see them.
func add_trap(id: int, pos: Vector3, visible_to_me: bool) -> void:
	var trap := Node3D.new()
	trap.visible = visible_to_me
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.45
	torus.outer_radius = 0.6
	ring.mesh = torus
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.4, 0.3, 0.7)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = mat
	ring.position.y = 0.06
	trap.add_child(ring)
	fx_root.add_child(trap)
	trap.global_position = pos
	_traps[id] = trap


func set_traps_visible(value: bool) -> void:
	for trap in _traps.values():
		trap.visible = value


func remove_trap(id: int) -> void:
	var trap: Node3D = _traps.get(id)
	if trap:
		_traps.erase(id)
		trap.queue_free()


func _ball_mesh(radius: float, color: Color, alpha: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(color, alpha)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	return mesh


func _add_timed(node: Node3D, pos: Vector3, lifetime: float) -> void:
	fx_root.add_child(node)
	node.global_position = pos
	get_tree().create_timer(lifetime).timeout.connect(func():
		if is_instance_valid(node):
			node.queue_free()
	)
