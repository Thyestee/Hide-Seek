extends CharacterBody3D
## One player. The local player reads input and owns its own movement; remote
## players ease toward the latest state the network gave us.
## Hiders play in third person (they need to see their disguise), seekers in
## first person with a mallet.

const PropLib = preload("res://scripts/world/prop_library.gd")

const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const JUMP_VELOCITY := 5.5
const SEEKER_EYE_HEIGHT := 1.55
const SWING_RANGE := 3.0
const SWING_COOLDOWN := 0.55
const MISS_PENALTY := 1.0
const MIMIC_RANGE := 5.0
const MIMIC_COOLDOWN := 1.5
const SEND_INTERVAL := 0.05
const SKIN := Color(0.96, 0.8, 0.66)

var peer_id := 0
var display_name := ""
var color := Color.WHITE
var is_local := false
var role := ""
var disguise := ""
var frozen := false
var rotation_locked := false
var body_yaw := 0.0
var look_prop := ""  # prop under the crosshair (local hider only)

var swing_cooldown := 0.0
var sonar_cooldown := 0.0
var taunt_cooldown := 0.0
var mimic_cooldown := 0.0

var collision: CollisionShape3D
var visual: Node3D
var model: Node3D
var mallet: Node3D
var name_tag: Label3D
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
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")


func setup(id: int, player_name: String, player_color: Color, local: bool) -> void:
	peer_id = id
	display_name = player_name
	color = player_color
	is_local = local
	set_meta("peer_id", id)
	collision_layer = 2
	collision_mask = 1 | 2
	collision = CollisionShape3D.new()
	add_child(collision)
	visual = Node3D.new()
	add_child(visual)
	name_tag = Label3D.new()
	name_tag.text = player_name
	name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_tag.font_size = 44
	name_tag.pixel_size = 0.006
	name_tag.outline_size = 12
	name_tag.modulate = player_color.lightened(0.35)
	name_tag.visible = false
	add_child(name_tag)
	if is_local:
		_build_camera()


func _ready() -> void:
	if is_local:
		camera.make_current()


func place_at(pos: Vector3) -> void:
	global_position = pos
	_target_pos = pos
	velocity = Vector3.ZERO
	if is_local:
		# Start facing away from the plaza centre, towards the village.
		var out := Vector3(pos.x, 0, pos.z)
		if out.length() > 0.1:
			cam_yaw.rotation.y = atan2(-out.x, -out.z)
			body_yaw = cam_yaw.rotation.y


func teleport(pos: Vector3) -> void:
	place_at(pos)


func apply_remote_state(pos: Vector3, yaw: float) -> void:
	_target_pos = pos
	_target_yaw = yaw


func set_role(new_role: String) -> void:
	role = new_role
	disguise = ""
	rotation_locked = false
	_rebuild_model()


func set_disguise(prop: String) -> void:
	disguise = prop
	if is_local:
		# Copy the orientation of the prop we mimicked, so we match its neighbours.
		body_yaw = _mimic_yaw
		rotation_locked = true
	_rebuild_model()
	visual.rotation.y = body_yaw


# --- Models ------------------------------------------------------------------

func _rebuild_model() -> void:
	if model:
		visual.remove_child(model)
		model.queue_free()
	mallet = null
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
		tag_height = PropLib.PROPS[disguise].size.y
	else:
		model = _build_hider_model()
	visual.add_child(model)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position.y = height * 0.5
	name_tag.position.y = tag_height + 0.45
	if is_local:
		_update_camera(height)


func _build_hider_model() -> Node3D:
	# A round little mimic creature. Models face -Z.
	var m := Node3D.new()
	PropLib.add_sphere(m, 0.42, Vector3(0, 0.46, 0), color, Vector3(1, 1.08, 1))
	for x in [-0.15, 0.15]:
		PropLib.add_sphere(m, 0.11, Vector3(x, 0.62, -0.34), Color(1, 1, 1))
		PropLib.add_sphere(m, 0.055, Vector3(x, 0.63, -0.43), Color(0.08, 0.08, 0.1))
		PropLib.add_sphere(m, 0.12, Vector3(x * 1.2, 0.06, -0.05), color.darkened(0.3), Vector3(1, 0.6, 1.3))
	PropLib.add_cyl(m, 0.02, 0.16, Vector3(0, 0.98, 0), PropLib.WOOD_DARK)
	PropLib.add_sphere(m, 0.08, Vector3(0.07, 1.06, 0), PropLib.LEAF, Vector3(1.4, 0.5, 0.8))
	return m


func _build_seeker_model() -> Node3D:
	var m := Node3D.new()
	var coat := Color(0.22, 0.24, 0.34)
	PropLib.add_cyl(m, 0.38, 1.1, Vector3(0, 0.55, 0), coat, 0.26)
	PropLib.add_cyl(m, 0.29, 0.12, Vector3(0, 0.95, 0), color)
	PropLib.add_sphere(m, 0.24, Vector3(0, 1.32, 0), SKIN)
	for x in [-0.09, 0.09]:
		PropLib.add_sphere(m, 0.045, Vector3(x, 1.36, -0.21), Color(0.08, 0.08, 0.1))
	PropLib.add_cyl(m, 0.44, 0.04, Vector3(0, 1.5, 0), coat.darkened(0.3))
	PropLib.add_cyl(m, 0.23, 0.26, Vector3(0, 1.64, 0), coat.darkened(0.3), 0.2)
	PropLib.add_cyl(m, 0.235, 0.06, Vector3(0, 1.55, 0), color)
	mallet = _build_mallet()
	mallet.position = Vector3(0.42, 0.85, -0.1)
	mallet.rotation_degrees = Vector3(-30, 0, 0)
	m.add_child(mallet)
	return m


func _build_mallet() -> Node3D:
	var m := Node3D.new()
	PropLib.add_cyl(m, 0.03, 0.65, Vector3(0, 0.3, 0), PropLib.WOOD)
	PropLib.add_cyl(m, 0.12, 0.34, Vector3(0, 0.66, 0), PropLib.WOOD_DARK, -1.0, Vector3(0, 0, PI / 2))
	PropLib.add_cyl(m, 0.125, 0.06, Vector3(0.14, 0.66, 0), color, -1.0, Vector3(0, 0, PI / 2))
	PropLib.add_cyl(m, 0.125, 0.06, Vector3(-0.14, 0.66, 0), color, -1.0, Vector3(0, 0, PI / 2))
	return m


func flash() -> void:
	var tween := create_tween()
	tween.tween_property(visual, "scale", Vector3(1.25, 0.8, 1.25), 0.06)
	tween.tween_property(visual, "scale", Vector3.ONE, 0.2).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func bounce() -> void:
	var tween := create_tween()
	tween.tween_property(visual, "position:y", 0.35, 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(visual, "position:y", 0.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func play_swing() -> void:
	if mallet == null:
		return
	var tween := create_tween()
	tween.tween_property(mallet, "rotation_degrees:x", -110.0, 0.08)
	tween.tween_property(mallet, "rotation_degrees:x", -30.0, 0.25)


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
	spring.add_child(camera)
	viewmodel = _build_mallet()
	viewmodel.position = Vector3(0.4, -0.55, -0.7)
	viewmodel.rotation_degrees = Vector3(-20, 0, -12)
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
	if role == "seeker":
		if event.is_action_pressed("swing"):
			_swing()
		elif event.is_action_pressed("sonar"):
			_sonar()
	elif role == "hider":
		if event.is_action_pressed("mimic"):
			_mimic()
		elif event.is_action_pressed("lock_rotation"):
			rotation_locked = not rotation_locked
		elif event.is_action_pressed("taunt"):
			_taunt()
		elif event.is_action_pressed("decoy"):
			_decoy()


func _physics_process(delta: float) -> void:
	if not is_local:
		_follow_network(delta)
		return
	swing_cooldown = maxf(swing_cooldown - delta, 0.0)
	sonar_cooldown = maxf(sonar_cooldown - delta, 0.0)
	taunt_cooldown = maxf(taunt_cooldown - delta, 0.0)
	mimic_cooldown = maxf(mimic_cooldown - delta, 0.0)

	var can_move := not frozen and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if can_move else Vector2.ZERO
	var direction := Vector3(input.x, 0, input.y).rotated(Vector3.UP, cam_yaw.rotation.y)
	var speed := SPRINT_SPEED if Input.is_action_pressed("sprint") else WALK_SPEED
	var blend := 1.0 - exp(-(12.0 if is_on_floor() else 3.0) * delta)
	velocity.x = lerpf(velocity.x, direction.x * speed, blend)
	velocity.z = lerpf(velocity.z, direction.z * speed, blend)
	if is_on_floor():
		if can_move and Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_VELOCITY
	else:
		velocity.y -= _gravity * delta
	move_and_slide()

	if role == "seeker" or not rotation_locked:
		body_yaw = cam_yaw.rotation.y
	visual.rotation.y = body_yaw
	if global_position.y < -15.0:
		teleport(Game.respawn_point(role))
	if role == "hider":
		_update_look_target()

	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		Game.send_state(global_position, body_yaw)


func _follow_network(delta: float) -> void:
	if global_position.distance_to(_target_pos) > 6.0:
		global_position = _target_pos
	else:
		global_position = global_position.lerp(_target_pos, 1.0 - exp(-15.0 * delta))
	body_yaw = _target_yaw
	visual.rotation.y = lerp_angle(visual.rotation.y, _target_yaw, 1.0 - exp(-15.0 * delta))


func _ray(length: float, mask: int) -> Dictionary:
	var from := camera.global_position
	var to := from - camera.global_basis.z * length
	var query := PhysicsRayQueryParameters3D.create(from, to, mask, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(query)


# --- Hider abilities ---------------------------------------------------------

func _update_look_target() -> void:
	look_prop = ""
	_look_body = null
	var hit := _ray(spring.spring_length + MIMIC_RANGE + 1.0, 1)
	if hit.is_empty():
		return
	var body: Object = hit.collider
	if body and body.has_meta("prop_type") and global_position.distance_to(hit.position) <= MIMIC_RANGE:
		look_prop = body.get_meta("prop_type")
		_look_body = body as Node3D


func _mimic() -> void:
	if look_prop == "" or mimic_cooldown > 0.0 or look_prop == disguise:
		return
	mimic_cooldown = MIMIC_COOLDOWN
	_mimic_yaw = _look_body.global_rotation.y if _look_body else body_yaw
	Game.request_disguise(look_prop)


func _taunt() -> void:
	if taunt_cooldown > 0.0:
		return
	taunt_cooldown = Game.TAUNT_COOLDOWN
	Game.request_taunt(randi() % Sfx.TAUNT_COUNT)


func _decoy() -> void:
	if disguise == "":
		Game.message.emit("Mimic a prop first, then drop a decoy copy of it.", Game.COLOR_INFO)
		return
	if Game.decoys_left <= 0:
		Game.message.emit("No decoys left this round.", Game.COLOR_INFO)
		return
	Game.request_decoy(global_position, body_yaw)


# --- Seeker abilities --------------------------------------------------------

func _swing() -> void:
	if swing_cooldown > 0.0:
		return
	swing_cooldown = SWING_COOLDOWN
	var tween := create_tween()
	tween.tween_property(viewmodel, "rotation_degrees:x", -95.0, 0.07)
	tween.tween_property(viewmodel, "rotation_degrees:x", -20.0, 0.25)
	Sfx.play("swing", -4.0)
	Game.broadcast_swing()
	if Game.phase != Game.Phase.SEEKING:
		return
	var hit := _ray(SWING_RANGE, 1 | 2)
	if hit.is_empty():
		return
	var body: Object = hit.collider
	if body == null:
		return
	if body.has_meta("peer_id"):
		var target: int = body.get_meta("peer_id")
		if Game.roles.get(target) == "hider":
			Game.request_hit(target)
	elif body.has_meta("decoy_id"):
		Game.request_decoy_hit(body.get_meta("decoy_id"))
	elif body.has_meta("prop_type"):
		# Bonking innocent furniture slows you down, so spamming doesn't pay.
		swing_cooldown += MISS_PENALTY
		Sfx.play_at("thud", hit.position)
		Game.message.emit("Just a %s... (slowed down)" % PropLib.display_name(body.get_meta("prop_type")).to_lower(), Game.COLOR_INFO)
		_wobble(body as Node3D)


func _wobble(body: Node3D) -> void:
	var prop_model := body.get_node_or_null("Model") as Node3D
	if prop_model == null:
		return
	var tween := create_tween()
	tween.tween_property(prop_model, "scale", Vector3(1.1, 0.9, 1.1), 0.06)
	tween.tween_property(prop_model, "scale", Vector3.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func _sonar() -> void:
	if sonar_cooldown > 0.0 or Game.phase != Game.Phase.SEEKING:
		return
	sonar_cooldown = Game.SONAR_COOLDOWN
	Game.request_sonar()
