extends CharacterBody3D
## One player. The local player reads input and owns its own movement; on the
## host, bots are driven the same way by a BotBrain; every other player eases
## toward the latest state the network gave us.
## Hiders play in third person (they need to see their disguise), seekers in
## first person with a bolt staff.

const PropLib = preload("res://scripts/world/prop_library.gd")
const MeshBatch = preload("res://scripts/world/mesh_batch.gd")
const Spells = preload("res://scripts/spells.gd")
const BotBrain = preload("res://scripts/player/bot_brain.gd")

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const JUMP_VELOCITY := 5.5
const SEEKER_EYE_HEIGHT := 1.55
const MIMIC_RANGE := 5.0
const MIMIC_COOLDOWN := 1.0
const SEND_INTERVAL := 0.05
const SKIN := Color(0.96, 0.8, 0.66)

var peer_id := 0
var display_name := ""
var color := Color.WHITE
var is_local := false
var is_bot := false  # driven by a BotBrain on this machine (host only)
var role := ""
var disguise := ""
var frozen := false
var rotation_locked := false
var body_yaw := 0.0
var look_pitch := 0.0
var look_prop := ""  # prop under the crosshair (local hider only)

# Bot controls, written by the BotBrain.
var bot_move := Vector3.ZERO
var bot_sprint := false
var bot_jump := false

# Status effects
var root_timer := 0.0
var haste_timer := 0.0
var reveal_timer := 0.0
var _dash_timer := 0.0
var _dash_velocity := Vector3.ZERO

var collision: CollisionShape3D
var visual: Node3D
var model: Node3D
var staff: Node3D
var name_tag: Label3D
var reveal_marker: Label3D
var cam_yaw: Node3D
var cam_pitch: Node3D
var spring: SpringArm3D
var camera: Camera3D
var viewmodel: Node3D

var _look_body: Node3D
var _mimic_yaw := 0.0
var _target_pos := Vector3.ZERO
var _target_yaw := 0.0
var _send_timer := 0.0
var _mimic_cooldown := 0.0
var _fire_cooldown := 0.0
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(id: int, player_name: String, player_color: Color, local: bool, bot: bool) -> void:
	peer_id = id
	display_name = player_name
	color = player_color
	is_local = local
	is_bot = bot
	set_meta("peer_id", id)
	collision_layer = 2
	collision_mask = 1 | 2
	collision = CollisionShape3D.new()
	add_child(collision)
	visual = Node3D.new()
	add_child(visual)
	name_tag = _label3d(player_name, 44, player_color.lightened(0.35), false)
	name_tag.visible = false
	add_child(name_tag)
	reveal_marker = _label3d("!", 120, Color(1.0, 0.85, 0.2), true)
	reveal_marker.visible = false
	add_child(reveal_marker)
	if is_local:
		_build_camera()
	if is_bot:
		var brain := BotBrain.new()
		brain.name = "Brain"
		add_child(brain)


func _label3d(text: String, size: int, tint: Color, through_walls: bool) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.font_size = size
	l.pixel_size = 0.006
	l.outline_size = 12
	l.modulate = tint
	l.no_depth_test = through_walls
	return l


func _ready() -> void:
	if is_local:
		camera.make_current()


func controlled_here() -> bool:
	return is_local or is_bot


func place_at(pos: Vector3) -> void:
	global_position = pos
	_target_pos = pos
	velocity = Vector3.ZERO
	# Start facing away from the plaza centre, towards the village.
	var out := Vector3(pos.x, 0, pos.z)
	if out.length() > 0.1:
		body_yaw = atan2(-out.x, -out.z)
		if is_local:
			cam_yaw.rotation.y = body_yaw


func teleport(pos: Vector3) -> void:
	place_at(pos)


func apply_remote_state(pos: Vector3, yaw: float) -> void:
	_target_pos = pos
	_target_yaw = yaw


func set_role(new_role: String) -> void:
	role = new_role
	disguise = ""
	rotation_locked = false
	root_timer = 0.0
	haste_timer = 0.0
	_rebuild_model()


func set_disguise(prop: String, yaw := INF) -> void:
	disguise = prop
	if controlled_here():
		# Copy the orientation of the prop we mimicked, so we match its neighbours.
		body_yaw = _mimic_yaw if yaw == INF else yaw
		rotation_locked = true
	_rebuild_model()
	visual.rotation.y = body_yaw


func look_direction() -> Vector3:
	if is_local:
		return -camera.global_basis.z
	return Vector3(-sin(body_yaw) * cos(look_pitch), sin(look_pitch), -cos(body_yaw) * cos(look_pitch))


func eye_position() -> Vector3:
	if is_local:
		return camera.global_position
	return global_position + Vector3.UP * (SEEKER_EYE_HEIGHT if role == "seeker" else 0.8)


# --- Effects -----------------------------------------------------------------

func dash(direction: Vector3) -> void:
	direction.y = 0
	if direction.length() < 0.1:
		direction = Vector3(-sin(body_yaw), 0, -cos(body_yaw))
	_dash_velocity = direction.normalized() * 22.0
	_dash_timer = 0.22


func reveal(duration: float) -> void:
	reveal_timer = maxf(reveal_timer, duration)


func flash() -> void:
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3(1.25, 0.8, 1.25), 0.06)
	tween.tween_property(visual, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func bounce() -> void:
	var tween := create_tween()
	tween.tween_property(visual, "position:y", 0.35, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func play_throw() -> void:
	var target := viewmodel if is_local else staff
	if target == null:
		return
	var rest: float = target.rotation_degrees.x
	var tween := create_tween()
	tween.tween_property(target, "rotation_degrees:x", rest - 35.0, 0.06)
	tween.tween_property(target, "rotation_degrees:x", rest, 0.2)


# --- Models ------------------------------------------------------------------

func _rebuild_model() -> void:
	if model:
		visual.remove_child(model)
		model.queue_free()
	staff = null
	var height := 1.0
	var radius := 0.4
	var tag_height := 1.0
	if role == "seeker":
		model = _build_seeker_model()
		height = 1.75
		radius = 0.35
		tag_height = 1.85
	elif disguise != "":
		model = PropLib.build_visual(disguise)
		var capsule := PropLib.capsule_for(disguise)
		radius = capsule.x
		height = capsule.y
		tag_height = PropLib.size_of(disguise).y
	else:
		model = _build_hider_model()
	visual.add_child(model)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position.y = height * 0.5
	name_tag.position.y = tag_height + 0.45
	reveal_marker.position.y = tag_height + 0.9
	if is_local:
		_update_camera(height)


func _build_hider_model() -> Node3D:
	# A round little mimic creature. Models face -Z.
	var b := MeshBatch.new()
	PropLib.sphere(b, 0.42, Vector3(0, 0.46, 0), color, Vector3(1, 1.08, 1))
	for x in [-0.15, 0.15]:
		PropLib.sphere(b, 0.11, Vector3(x, 0.62, -0.34), Color(1, 1, 1))
		PropLib.sphere(b, 0.055, Vector3(x, 0.63, -0.43), Color(0.08, 0.08, 0.1))
		PropLib.sphere(b, 0.12, Vector3(x * 1.2, 0.06, -0.05), color.darkened(0.3), Vector3(1, 0.6, 1.3))
	PropLib.cyl(b, 0.02, 0.16, Vector3(0, 0.98, 0), PropLib.WOOD_DARK)
	PropLib.sphere(b, 0.08, Vector3(0.07, 1.06, 0), PropLib.LEAF, Vector3(1.4, 0.5, 0.8))
	var m := Node3D.new()
	m.add_child(b.build_instance())
	return m


func _build_seeker_model() -> Node3D:
	var coat := Color(0.22, 0.24, 0.34)
	var b := MeshBatch.new()
	PropLib.cyl(b, 0.38, 1.1, Vector3(0, 0.55, 0), coat, 0.26)
	PropLib.cyl(b, 0.29, 0.12, Vector3(0, 0.95, 0), color)
	PropLib.sphere(b, 0.24, Vector3(0, 1.32, 0), SKIN)
	for x in [-0.09, 0.09]:
		PropLib.sphere(b, 0.045, Vector3(x, 1.36, -0.21), Color(0.08, 0.08, 0.1))
	PropLib.cyl(b, 0.44, 0.04, Vector3(0, 1.5, 0), coat.darkened(0.3))
	PropLib.cyl(b, 0.23, 0.26, Vector3(0, 1.64, 0), coat.darkened(0.3), 0.2)
	PropLib.cyl(b, 0.25, 0.06, Vector3(0, 1.55, 0), color)
	var m := Node3D.new()
	m.add_child(b.build_instance())
	staff = _build_staff()
	staff.position = Vector3(0.42, 0.4, -0.1)
	staff.rotation_degrees = Vector3(-20, 0, 0)
	m.add_child(staff)
	return m


## The seekers' weapon: a staff with a glowing orb that throws bolts.
func _build_staff() -> Node3D:
	var b := MeshBatch.new()
	PropLib.cyl(b, 0.03, 1.1, Vector3(0, 0.55, 0), PropLib.WOOD)
	PropLib.cyl(b, 0.06, 0.08, Vector3(0, 1.12, 0), color)
	PropLib.sphere(b, 0.09, Vector3(0, 1.22, 0), Color(0.6, 0.92, 1.0), Vector3.ONE, Vector3.ZERO, true)
	var s := Node3D.new()
	s.add_child(b.build_instance())
	return s


# --- Camera ------------------------------------------------------------------

func _build_camera() -> void:
	cam_yaw = Node3D.new()
	add_child(cam_yaw)
	cam_pitch = Node3D.new()
	cam_yaw.add_child(cam_pitch)
	spring = SpringArm3D.new()
	spring.collision_mask = 1
	spring.margin = 0.15
	var probe := SphereShape3D.new()
	probe.radius = 0.2
	spring.shape = probe
	spring.add_excluded_object(get_rid())
	cam_pitch.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 80.0
	camera.near = 0.05
	camera.far = 260.0  # a short range keeps depth precise, so nothing flickers
	spring.add_child(camera)
	viewmodel = _build_staff()
	viewmodel.position = Vector3(0.55, -1.3, -0.95)
	viewmodel.rotation_degrees = Vector3(-22, 0, -14)
	camera.add_child(viewmodel)


func _update_camera(height: float) -> void:
	if role == "seeker":
		cam_pitch.position = Vector3(0, SEEKER_EYE_HEIGHT, 0)
		spring.spring_length = 0.0
		viewmodel.visible = true
		_set_shadow_only(model)
	else:
		cam_pitch.position = Vector3(0, maxf(height * 0.75, 0.7), 0)
		spring.spring_length = clampf(2.5 + height, 3.2, 5.0)
		viewmodel.visible = false


## Hides our own body from our first-person camera but keeps its shadow.
func _set_shadow_only(node: Node) -> void:
	if node is GeometryInstance3D:
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	for child in node.get_children():
		_set_shadow_only(child)


# --- Input and movement ------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not is_local or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var sensitivity := 0.0025 * Net.mouse_sensitivity
		cam_yaw.rotate_y(-event.relative.x * sensitivity)
		cam_pitch.rotation.x = clampf(cam_pitch.rotation.x - event.relative.y * sensitivity, deg_to_rad(-85), deg_to_rad(75))
		return
	if frozen:
		return
	if event.is_action_pressed("spell1"):
		cast_spell(0)
	elif event.is_action_pressed("spell2"):
		cast_spell(1)
	elif role == "hider":
		if event.is_action_pressed("mimic"):
			_mimic()
		elif event.is_action_pressed("lock_rotation"):
			rotation_locked = not rotation_locked
		elif event.is_action_pressed("taunt"):
			_taunt()


func _physics_process(delta: float) -> void:
	_tick_effects(delta)
	if not controlled_here():
		_follow_network(delta)
		return
	_fire_cooldown = maxf(_fire_cooldown - delta, 0.0)
	_mimic_cooldown = maxf(_mimic_cooldown - delta, 0.0)

	var direction := Vector3.ZERO
	var sprint := false
	var jump := false
	var can_move := not frozen and root_timer <= 0.0
	if is_local:
		can_move = can_move and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		if can_move:
			var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
			direction = Vector3(input.x, 0, input.y).rotated(Vector3.UP, cam_yaw.rotation.y)
			sprint = Input.is_action_pressed("sprint")
			jump = Input.is_action_just_pressed("jump")
			if role == "seeker" and Input.is_action_pressed("throw"):
				_throw()
	elif can_move:
		direction = bot_move
		sprint = bot_sprint
		jump = bot_jump
		bot_jump = false

	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	if haste_timer > 0.0:
		speed *= 1.6
	var blend := 1.0 - exp(-(12.0 if is_on_floor() else 3.0) * delta)
	velocity.x = lerpf(velocity.x, direction.x * speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * speed, blend)
	if _dash_timer > 0.0:
		velocity.x = _dash_velocity.x
		velocity.z = _dash_velocity.z
	if is_on_floor():
		if jump:
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	if is_local and (role == "seeker" or not rotation_locked):
		body_yaw = cam_yaw.rotation.y
	if is_local:
		look_pitch = cam_pitch.rotation.x
	visual.rotation.y = body_yaw
	if global_position.y < -15.0:
		teleport(Game.respawn_point(role))
	if is_local and role == "hider":
		_update_look_target()

	if is_local:
		_send_timer += delta
		if _send_timer >= SEND_INTERVAL:
			_send_timer = 0.0
			Game.send_state(global_position, body_yaw)


func _tick_effects(delta: float) -> void:
	root_timer = maxf(root_timer - delta, 0.0)
	haste_timer = maxf(haste_timer - delta, 0.0)
	_dash_timer = maxf(_dash_timer - delta, 0.0)
	reveal_timer = maxf(reveal_timer - delta, 0.0)
	reveal_marker.visible = reveal_timer > 0.0


func _follow_network(delta: float) -> void:
	if global_position.distance_to(_target_pos) > 6.0:
		global_position = _target_pos
	else:
		global_position = global_position.lerp(_target_pos, 1.0 - exp(-15.0 * delta))
	body_yaw = _target_yaw
	visual.rotation.y = lerp_angle(visual.rotation.y, _target_yaw, 1.0 - exp(-15.0 * delta))


func _ray(from: Vector3, direction: Vector3, length: float, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, from + direction * length, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


# --- Actions (used by local input and by bots) -------------------------------

func _update_look_target() -> void:
	look_prop = ""
	_look_body = null
	var hit := _ray(camera.global_position, -camera.global_basis.z, spring.spring_length + MIMIC_RANGE + 1.0, 1)
	if hit.is_empty():
		return
	var body: Object = hit.collider
	if body and body.has_meta("prop_type") and global_position.distance_to(hit.position) <= MIMIC_RANGE:
		look_prop = body.get_meta("prop_type")
		_look_body = body as Node3D


func _mimic() -> void:
	if look_prop == "" or _mimic_cooldown > 0.0 or look_prop == disguise:
		return
	_mimic_cooldown = MIMIC_COOLDOWN
	_mimic_yaw = _look_body.global_rotation.y if _look_body else body_yaw
	Game.request_disguise(look_prop)


func mimic_as(prop: String, yaw: float) -> void:
	_mimic_yaw = yaw
	Game.request_disguise_for(peer_id, prop)


func _taunt() -> void:
	if Game.cooldown_left(peer_id, "taunt") > 0.0:
		return
	Game.request_taunt(randi() % Sfx.TAUNT_COUNT)


func _throw() -> void:
	if _fire_cooldown > 0.0 or Game.phase != Game.Phase.SEEKING:
		return
	if Game.local_charges() < 1.0:
		return
	_fire_cooldown = Game.BOLT_INTERVAL
	play_throw()
	Game.request_throw(eye_position() + look_direction() * 0.6, look_direction())


## Casts the spell in loadout slot 0 or 1, with whatever aim data it needs.
func cast_spell(slot: int) -> void:
	var spell := Game.spell_in_slot(peer_id, slot)
	if spell == "" or Game.cooldown_left(peer_id, spell) > 0.0:
		return
	var data := {
		"pos": global_position, "yaw": body_yaw,
		"origin": eye_position() + look_direction() * 0.6, "dir": look_direction(),
		"move": velocity,
	}
	if spell == "echo":
		var hit := _ray(eye_position(), look_direction(), 40.0, 1)
		data.target = hit.position if not hit.is_empty() else eye_position() + look_direction() * 25.0
	Game.request_spell(peer_id, slot, data)
