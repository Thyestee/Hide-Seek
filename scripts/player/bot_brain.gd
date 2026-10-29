extends Node
## Simple AI for a bot player. It runs on the host only, steers its player
## along the navigation mesh and acts through the same Game functions people use.
##
## Hiders pick a prop somewhere in the village, walk next to it, copy it and keep
## still; when hurt they run somewhere else. Seekers wander, test props by
## shooting them, and go after hiders they notice moving or that a spell gave away.

const PropLib = preload("res://scripts/world/prop_library.gd")

const SIGHT_RANGE := 16.0
const SHOT_RANGE := 13.0

var player: CharacterBody3D
var agent: NavigationAgent3D
var _rng := RandomNumberGenerator.new()
var _think := 0.0
var _goal := Vector3.INF
var _goal_prop: Node3D
var _settled := false
var _last_hp := 0
var _stuck_timer := 0.0
var _last_spot := Vector3.ZERO
var _chase: Node3D
var _chase_timer := 0.0
var _suspects := {}  # prop body or player -> how many times we checked it
var _seen := {}      # hider -> where we last saw it, to notice movement


func _ready() -> void:
	player = get_parent()
	_rng.randomize()
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.7
	agent.target_desired_distance = 1.0
	agent.radius = 0.5
	player.add_child.call_deferred(agent)


func _physics_process(delta: float) -> void:
	player.bot_move = Vector3.ZERO
	player.bot_sprint = false
	if Game.world == null or not Game.world.nav_ready or player.frozen or agent == null or not agent.is_inside_tree():
		return
	_think -= delta
	if player.role == "hider":
		_hider(delta)
	elif player.role == "seeker":
		_seeker(delta)
	_steer(delta)


# --- Hider -------------------------------------------------------------------

func _hider(_delta: float) -> void:
	var hp: int = Game.hp.get(player.peer_id, 0)
	var hurt := hp < _last_hp
	_last_hp = hp
	if hurt and Game.phase == Game.Phase.SEEKING:
		_flee()
	if _think > 0.0:
		return
	_think = _rng.randf_range(0.4, 0.8)
	if _goal == Vector3.INF and not _settled:
		_pick_hiding_spot()
	elif not _settled and _arrived():
		_settle()
	elif _settled:
		# Mostly sit still; the odd taunt or spell keeps it lively.
		if Game.phase == Game.Phase.SEEKING and _rng.randf() < 0.015:
			Game.bot_taunt(player.peer_id)
		if hp < Game.max_hp_of(player.peer_id) * 0.4:
			_try_spell("regrow")
		if _rng.randf() < 0.02:
			_try_spell("clutter")
		if _rng.randf() < 0.01:
			_try_spell("echo", {"target": player.global_position + Vector3(_rng.randf_range(-15, 15), 0, _rng.randf_range(-15, 15))})


func _pick_hiding_spot() -> void:
	var props: Array = Game.world.map_props
	for attempt in 12:
		var body: Node3D = props[_rng.randi() % props.size()]
		var offset := Vector3(_rng.randf_range(-1.6, 1.6), 0, _rng.randf_range(-1.6, 1.6))
		if body.global_position.y > 0.3 or offset.length() < 0.9:
			continue  # skip things on tables and spots right on top of the prop
		_goal_prop = body
		_go(body.global_position + offset)
		return


func _settle() -> void:
	_settled = true
	_goal = Vector3.INF
	var prop := "barrel"
	var yaw := 0.0
	if is_instance_valid(_goal_prop):
		prop = _goal_prop.get_meta("prop_type")
		yaw = _goal_prop.global_rotation.y
	if player.disguise != prop:
		player.mimic_as(prop, yaw)
	if _rng.randf() < 0.5:
		_try_spell("decoy", {"yaw": yaw})


func _flee() -> void:
	_settled = false
	_try_spell("smoke")
	_try_spell("blink", {"move": -player.global_basis.z})
	var props: Array = Game.world.map_props
	for attempt in 10:
		var body: Node3D = props[_rng.randi() % props.size()]
		if body.global_position.y < 0.3 and body.global_position.distance_to(player.global_position) > 15.0:
			_goal_prop = body
			_go(body.global_position + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5)))
			break
	_think = 0.3


# --- Seeker ------------------------------------------------------------------

func _seeker(delta: float) -> void:
	if Game.phase != Game.Phase.SEEKING:
		return
	_chase_timer -= delta
	if _chase and (not is_instance_valid(_chase) or _chase_timer <= 0.0 or (_chase.has_meta("peer_id") and _chase.role != "hider")):
		_chase = null
	if _think > 0.0:
		return
	_think = _rng.randf_range(0.35, 0.7)

	var target := _pick_target()
	if target:
		_chase = target
		_chase_timer = 6.0
	if _chase:
		var aim: Vector3 = _chase.global_position + Vector3.UP * 0.4
		var distance := player.global_position.distance_to(aim)
		_face(aim)
		if distance > 4.0:
			_go(_chase.global_position)
		else:
			_goal = Vector3.INF
		if distance <= SHOT_RANGE and _can_see(aim, _chase):
			_shoot(aim, distance)
			_suspects[_chase] = _suspects.get(_chase, 0) + 1
			if _chase.has_meta("peer_id"):
				if distance < Game.SHOCKWAVE_RADIUS:
					_try_spell("shockwave")
				_try_spell("scatter")
			elif _suspects[_chase] >= 2:
				_chase = null  # it didn't flinch: just furniture
	else:
		if _goal == Vector3.INF or _arrived():
			_wander()
		if _rng.randf() < 0.08:
			_try_spell("sonar")
		if _rng.randf() < 0.04:
			_try_spell("snare")
		if _rng.randf() < 0.03:
			_try_spell("flare")
		if _rng.randf() < 0.03:
			_try_spell("haste")


## What a seeker notices: revealed or moving hiders first, otherwise now and
## then a hider it happens to be close to, or a random nearby prop to test.
func _pick_target() -> Node3D:
	var best: Node3D = null
	for p in Game.world.get_players():
		if p.role != "hider":
			continue
		var d := player.global_position.distance_to(p.global_position)
		if d > SIGHT_RANGE or not _can_see(p.global_position + Vector3.UP * 0.4, p):
			continue
		var moving: bool = p.global_position.distance_to(_seen.get(p, p.global_position)) > 0.3
		_seen[p] = p.global_position
		var obvious: bool = p.reveal_timer > 0.0 or p.disguise == "" or moving
		if obvious or (d < 6.0 and _rng.randf() < 0.12):
			best = p
	if best or _chase:
		return best
	if _rng.randf() < 0.35:
		var props: Array = Game.world.map_props
		for attempt in 6:
			var body: Node3D = props[_rng.randi() % props.size()]
			var d := player.global_position.distance_to(body.global_position)
			if d < 10.0 and _suspects.get(body, 0) < 1 and _can_see(body.global_position + Vector3.UP * 0.3, body):
				return body
	return null


func _wander() -> void:
	var props: Array = Game.world.map_props
	var body: Node3D = props[_rng.randi() % props.size()]
	_go(body.global_position + Vector3(_rng.randf_range(-2, 2), 0, _rng.randf_range(-2, 2)))


func _shoot(aim: Vector3, distance: float) -> void:
	var origin: Vector3 = player.global_position + Vector3.UP * 1.5
	# Aim a little high for the bolt's drop, and not perfectly.
	var t := distance / Game.BOLT_SPEED
	var drop := 0.5 * Game.BOLT_GRAVITY * t * t
	var dir := (aim + Vector3.UP * drop - origin).normalized()
	dir = (dir + Vector3(_rng.randf_range(-0.03, 0.03), _rng.randf_range(-0.02, 0.02), _rng.randf_range(-0.03, 0.03))).normalized()
	if Game.bot_throw(player.peer_id, origin + dir * 0.6, dir):
		player.play_throw()


func _can_see(point: Vector3, target: Object) -> bool:
	var exclude: Array[RID] = [player.get_rid()]
	if target is CollisionObject3D:
		exclude.append(target.get_rid())
	var query := PhysicsRayQueryParameters3D.create(player.global_position + Vector3.UP * 1.5, point, 1, exclude)
	return player.get_world_3d().direct_space_state.intersect_ray(query).is_empty()


# --- Shared ------------------------------------------------------------------

func _try_spell(spell: String, data := {}) -> void:
	for slot in 2:
		if Game.spell_in_slot(player.peer_id, slot) == spell and Game.cooldown_left(player.peer_id, spell) <= 0.0:
			var full := {
				"pos": player.global_position, "yaw": player.body_yaw,
				"origin": player.global_position + Vector3.UP * 1.5,
				"dir": player.look_direction(), "move": player.velocity,
			}
			full.merge(data, true)
			Game.request_spell(player.peer_id, slot, full)
			return


func _go(point: Vector3) -> void:
	_goal = point
	agent.target_position = point
	_stuck_timer = 0.0
	_last_spot = player.global_position


func _arrived() -> bool:
	return _goal != Vector3.INF and (agent.is_navigation_finished() or player.global_position.distance_to(_goal) < 1.2)


func _face(point: Vector3) -> void:
	var to := point - (player.global_position + Vector3.UP * 1.5)
	player.body_yaw = atan2(-to.x, -to.z)
	player.look_pitch = atan2(to.y, Vector2(to.x, to.z).length())


func _steer(delta: float) -> void:
	if _goal == Vector3.INF or agent.is_navigation_finished():
		return
	var next := agent.get_next_path_position()
	var to := next - player.global_position
	to.y = 0
	if to.length() < 0.05:
		return
	player.bot_move = to.normalized()
	player.bot_sprint = player.role == "seeker" or not _settled
	if player.role == "hider" and not _settled:
		player.body_yaw = atan2(-to.x, -to.z)
	elif player.role == "seeker" and _chase == null:
		player.body_yaw = atan2(-to.x, -to.z)
		player.look_pitch = 0.0
	# Unstick: if we've barely moved for a while, hop and pick a new goal.
	_stuck_timer += delta
	if _stuck_timer > 2.5:
		if player.global_position.distance_to(_last_spot) < 0.8:
			player.bot_jump = true
			_goal = Vector3.INF
		_stuck_timer = 0.0
		_last_spot = player.global_position
