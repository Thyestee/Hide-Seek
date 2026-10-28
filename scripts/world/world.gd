extends Node3D
## The playable world: lighting, the village map, players, decoys and effects.

const MapBuilder = preload("res://scripts/world/map_builder.gd")
const PropLib = preload("res://scripts/world/prop_library.gd")
const PlayerScript = preload("res://scripts/player/player.gd")

var players_root: Node3D
var decoys_root: Node3D
var hider_spawns: Array[Vector3] = []
var seeker_spawns: Array[Vector3] = []


func _ready() -> void:
	_build_environment()
	var builder := MapBuilder.new()
	builder.build(self)
	hider_spawns = builder.hider_spawns
	seeker_spawns = builder.seeker_spawns
	players_root = Node3D.new()
	players_root.name = "Players"
	add_child(players_root)
	decoys_root = Node3D.new()
	decoys_root.name = "Decoys"
	add_child(decoys_root)


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
	sun.directional_shadow_max_distance = 70.0
	add_child(sun)


# --- Players -----------------------------------------------------------------

func spawn_player(id: int, role: String, pos: Vector3) -> Node:
	var p := PlayerScript.new()
	p.name = str(id)
	p.setup(id, Net.get_player_name(id), Net.get_player_color(id), id == multiplayer.get_unique_id())
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


func clear_decoys() -> void:
	for d in decoys_root.get_children():
		decoys_root.remove_child(d)
		d.queue_free()


# --- Effects -----------------------------------------------------------------

func puff(pos: Vector3, color: Color) -> void:
	var particles := CPUParticles3D.new()
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 0.8
	particles.explosiveness = 1.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	mesh.radial_segments = 8
	mesh.rings = 4
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color.lightened(0.4)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	particles.mesh = mesh
	particles.direction = Vector3.UP
	particles.spread = 180.0
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 4.5
	particles.gravity = Vector3(0, -3, 0)
	particles.damping_min = 3.0
	particles.damping_max = 5.0
	particles.scale_amount_min = 0.6
	particles.scale_amount_max = 1.6
	add_child(particles)
	particles.global_position = pos
	particles.emitting = true
	get_tree().create_timer(1.5).timeout.connect(particles.queue_free)


## An expanding see-through bubble showing the sonar's reach.
func sonar_wave(pos: Vector3, radius: float) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.85, 1.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var wave := MeshInstance3D.new()
	wave.mesh = mesh
	wave.material_override = mat
	wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wave)
	wave.global_position = pos
	wave.scale = Vector3.ONE * 0.5
	var tween := wave.create_tween().set_parallel()
	tween.tween_property(wave, "scale", Vector3.ONE * radius, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.8)
	tween.chain().tween_callback(wave.queue_free)
