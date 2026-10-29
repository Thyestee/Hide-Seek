extends Node
## Round logic. The host is the authority: clients send requests, the host
## checks them and broadcasts the result to everyone (itself included).
## Bots live on the host and go through the same checks as real players.
## Every peer keeps a mirror of the round state so the HUD can read it.

signal entered_game
signal left_game
signal phase_changed(phase: int)
signal roles_changed
signal scores_changed
signal message(text: String, color: Color)
signal round_ended(winner: String)
signal local_hit(hp: int)
signal hit_confirmed

enum Phase { LOBBY, HIDING, SEEKING, ROUND_END }

const WorldScript = preload("res://scripts/world/world.gd")
const PropLib = preload("res://scripts/world/prop_library.gd")
const Spells = preload("res://scripts/spells.gd")

const ROUND_END_TIME := 10.0
const FORCED_TAUNT_WINDOW := 60.0
const FORCED_TAUNT_INTERVAL := 20.0
const SEEKER_RATIO := 0.2
const CATCH_POINTS := 100
const SURVIVE_POINTS := 200
const TAUNT_POINTS := 10
const TAUNT_COOLDOWN := 6.0
# Health
const REGEN_DELAY := 5.0
const REGEN_RATE := 6.0
# Seeker bolts
const BOLT_DAMAGE := 20
const BOLT_SPEED := 34.0
const BOLT_GRAVITY := 5.0
const BOLT_LIFE := 1.6
const BOLT_CHARGES := 5.0
const BOLT_RECHARGE := 0.7
const BOLT_INTERVAL := 0.25
# Spells
const SONAR_RADIUS := 14.0
const FLARE_RADIUS := 6.0
const REVEAL_TIME := 4.0
const SNARE_RADIUS := 0.9
const SNARE_ROOT := 3.0
const MAX_SNARES := 2
const SHOCKWAVE_RADIUS := 4.0
const SHOCKWAVE_DAMAGE := 15
const SMOKE_TIME := 7.0
const REGROW_HP := 40
const HASTE_TIME := 4.0

const COLOR_INFO := Color(0.85, 0.9, 1.0)
const COLOR_GOOD := Color(0.5, 1.0, 0.55)
const COLOR_BAD := Color(1.0, 0.5, 0.45)

var hide_time := 40.0
var seek_time := 240.0

var phase := Phase.LOBBY
var time_left := 0.0
var round_num := 0
var roles := {}      # peer id -> "hider" / "seeker"
var hp := {}         # peer id -> int
var disguises := {}  # peer id -> prop id ("" while not disguised)
var scores := {}     # peer id -> int
var world: Node3D = null

var _cooldowns := {}  # peer id -> {spell id or "taunt": end time}
var _charges := {}    # peer id -> bolts ready (float)
var _key_labels := {}

# Host-only bookkeeping.
var _last_pos := {}
var _last_damage := {}
var _decoys := {}  # decoy id -> [prop, position, yaw]
var _next_decoy_id := 1
var _projectiles := {}
var _next_projectile_id := 1
var _snares := {}  # trap id -> {pos, owner}
var _next_snare_id := 1
var _seeker_history := {}
var _solo_round := false
var _sync_timer := 0.0
var _bot_sync_timer := 0.0
var _regen_timer := 0.0
var _forced_taunt_timer := 0.0


func _ready() -> void:
	_setup_input()


func _process(delta: float) -> void:
	if world == null or phase == Phase.LOBBY:
		return
	time_left = maxf(time_left - delta, 0.0)
	for id in _charges:
		_charges[id] = minf(_charges[id] + delta / BOLT_RECHARGE, BOLT_CHARGES)
	if not Net.is_host():
		return
	_sync_timer += delta
	if _sync_timer >= 2.0:
		_sync_timer = 0.0
		rpc("rpc_sync_time", phase, time_left)
	_bot_sync_timer += delta
	if _bot_sync_timer >= 0.05:
		_bot_sync_timer = 0.0
		_broadcast_bots()
	_regen_timer += delta
	if _regen_timer >= 0.5:
		_regen_timer = 0.0
		_regenerate()
	match phase:
		Phase.HIDING:
			if time_left <= 0.0:
				rpc("rpc_set_phase", Phase.SEEKING, seek_time)
		Phase.SEEKING:
			if time_left <= FORCED_TAUNT_WINDOW:
				_forced_taunt_timer -= delta
				if _forced_taunt_timer <= 0.0:
					_forced_taunt_timer = FORCED_TAUNT_INTERVAL
					_force_taunts()
			if time_left <= 0.0:
				_end_round("hiders")
		Phase.ROUND_END:
			if time_left <= 0.0:
				_start_round()


func _physics_process(delta: float) -> void:
	if world == null or not Net.is_host():
		return
	_step_projectiles(delta)
	_check_snares()


# --- Queries -----------------------------------------------------------------

func in_game() -> bool:
	return world != null


func my_id() -> int:
	return multiplayer.get_unique_id()


func my_role() -> String:
	return roles.get(my_id(), "")


func count_role(role: String) -> int:
	var n := 0
	for id in roles:
		if roles[id] == role:
			n += 1
	return n


func get_player(id: int) -> Node:
	return world.get_player(id) if world else null


func local_player() -> Node:
	return get_player(my_id())


func max_hp_of(id: int) -> int:
	return PropLib.max_hp_for(disguises.get(id, ""))


func respawn_point(role: String) -> Vector3:
	var points: Array = world.seeker_spawns if role == "seeker" else world.hider_spawns
	return points.pick_random() + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))


func spell_in_slot(id: int, slot: int) -> String:
	var team: String = roles.get(id, "")
	var loadout: Dictionary = Net.players.get(id, {}).get("loadout", Spells.DEFAULT_LOADOUT)
	var picks: Array = loadout.get(team, [])
	return picks[slot] if slot < picks.size() else ""


func cooldown_left(id: int, key: String) -> float:
	return maxf(_cooldowns.get(id, {}).get(key, 0.0) - _now(), 0.0)


func local_charges() -> float:
	return _charges.get(my_id(), BOLT_CHARGES)


## The key the player actually has to press, following their keyboard layout.
func key_label(action: String) -> String:
	if _key_labels.has(action):
		return _key_labels[action]
	var label := "?"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key: Key = event.physical_keycode
			if DisplayServer.get_name() != "headless":
				var mapped := DisplayServer.keyboard_get_label_from_physical(key)
				if mapped != KEY_NONE:
					key = mapped
			label = OS.get_keycode_string(key)
			break
		if event is InputEventMouseButton:
			label = "LMB" if event.button_index == MOUSE_BUTTON_LEFT else "RMB"
			break
	_key_labels[action] = label
	return label


# --- Lobby -> game -----------------------------------------------------------

func host_start_game(hide: float, seek: float) -> void:
	if not Net.is_host() or in_game():
		return
	hide_time = hide
	seek_time = seek
	round_num = 0
	scores.clear()
	for id in Net.players:
		scores[id] = 0
	rpc("rpc_enter_game")
	if world.nav_ready:
		_start_round()
	else:
		# Give the bots' navigation mesh a moment to bake before the first round.
		world.navigation_ready.connect(_start_round, CONNECT_ONE_SHOT)


func host_return_to_lobby() -> void:
	if Net.is_host():
		rpc("rpc_return_to_lobby")


@rpc("authority", "call_local", "reliable")
func rpc_enter_game() -> void:
	if world:
		return
	world = WorldScript.new()
	world.name = "World"
	get_tree().current_scene.add_child(world)
	entered_game.emit()


@rpc("authority", "call_local", "reliable")
func rpc_return_to_lobby() -> void:
	_clear_round()
	left_game.emit()


## Drops everything about the current game, e.g. after a disconnect.
func reset() -> void:
	var was_in_game := world != null
	_clear_round()
	scores.clear()
	round_num = 0
	_seeker_history.clear()
	if was_in_game:
		left_game.emit()


func _clear_round() -> void:
	if world:
		world.queue_free()
		world = null
	phase = Phase.LOBBY
	roles.clear()
	hp.clear()
	disguises.clear()
	_cooldowns.clear()
	_charges.clear()
	_last_pos.clear()
	_last_damage.clear()
	_decoys.clear()
	_projectiles.clear()
	_snares.clear()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# --- Rounds (host) -----------------------------------------------------------

func _start_round() -> void:
	var ids: Array = Net.players.keys()
	ids.sort()
	if ids.is_empty() or world == null:
		return
	round_num += 1
	_solo_round = ids.size() == 1
	var seekers := _pick_seekers(ids)
	var new_roles := {}
	var spawns := {}
	var hider_index: int = randi() % world.hider_spawns.size()
	var seeker_index := 0
	for id in ids:
		if id in seekers:
			new_roles[id] = "seeker"
			spawns[id] = world.seeker_spawns[seeker_index % world.seeker_spawns.size()]
			seeker_index += 1
		else:
			new_roles[id] = "hider"
			spawns[id] = world.hider_spawns[hider_index % world.hider_spawns.size()]
			hider_index += 1
		scores[id] = scores.get(id, 0)
		_last_pos[id] = spawns[id]
	_decoys.clear()
	_projectiles.clear()
	_snares.clear()
	_last_damage.clear()
	_forced_taunt_timer = 0.0
	_sync_timer = 0.0
	rpc("rpc_begin_round", round_num, new_roles, spawns, hide_time, scores)


## Players who asked for a team get it when possible; "auto" players fill in,
## and whoever has sought least so far goes first.
func _pick_seekers(ids: Array) -> Array:
	if ids.size() == 1:
		return []  # Practice round: a lone player explores as a hider.
	var target := clampi(roundi(ids.size() * SEEKER_RATIO), 1, ids.size() - 1)
	var wants_seek := []
	var auto := []
	var wants_hide := []
	for id in ids:
		match Net.players[id].get("team", "auto"):
			"seeker": wants_seek.append(id)
			"hider": wants_hide.append(id)
			_: auto.append(id)
	var by_history := func(a, b): return _seeker_history.get(a, 0) < _seeker_history.get(b, 0)
	for pool in [wants_seek, auto, wants_hide]:
		pool.shuffle()
		pool.sort_custom(by_history)
	var picked: Array = wants_seek.slice(0, ids.size() - 1)
	for id in auto + wants_hide:
		if picked.size() >= target:
			break
		picked.append(id)
	for id in picked:
		_seeker_history[id] = _seeker_history.get(id, 0) + 1
	return picked


func _end_round(winner: String) -> void:
	if winner == "hiders":
		for id in roles:
			if roles[id] == "hider":
				scores[id] = scores.get(id, 0) + SURVIVE_POINTS
	rpc("rpc_end_round", winner, scores)


func _check_round_over() -> void:
	if phase != Phase.HIDING and phase != Phase.SEEKING:
		return
	if count_role("hider") == 0:
		_end_round("seekers")
	elif count_role("seeker") == 0 and not _solo_round:
		_end_round("hiders")


func _force_taunts() -> void:
	var any := false
	for id in roles:
		if roles[id] == "hider":
			any = true
			rpc("rpc_play_taunt", id, randi() % Sfx.TAUNT_COUNT, scores, 0.0)
	if any:
		rpc("rpc_message", "The hiders can't keep quiet any more...", COLOR_INFO)


func _regenerate() -> void:
	if phase != Phase.SEEKING and phase != Phase.HIDING:
		return
	for id in roles:
		if roles[id] != "hider" or _now() - _last_damage.get(id, -100.0) < REGEN_DELAY:
			continue
		var current: int = hp.get(id, 0)
		var top := max_hp_of(id)
		if current < top:
			rpc("rpc_hp", id, mini(top, current + ceili(REGEN_RATE * 0.5)), 0, false)


## Called by Net once a new player (or bot) has joined.
func on_player_registered(id: int) -> void:
	scores[id] = scores.get(id, 0)
	if world == null:
		return
	# Late joiners help seek, so they're never stuck waiting for the next round.
	var spawn := respawn_point("seeker")
	roles[id] = "seeker"
	disguises[id] = ""
	hp[id] = max_hp_of(id)
	_last_pos[id] = spawn
	if not Net.is_bot(id):
		var state := {
			"phase": phase, "time_left": time_left, "round": round_num, "roles": roles,
			"hp": hp, "disguises": disguises, "scores": scores, "positions": _last_pos,
			"decoys": _decoys,
		}
		rpc_id(id, "rpc_enter_game")
		rpc_id(id, "rpc_full_state", state)
	rpc("rpc_add_player", id, "seeker", spawn, scores)


func on_peer_left(id: int) -> void:
	var was_playing := roles.has(id)
	roles.erase(id)
	hp.erase(id)
	disguises.erase(id)
	scores.erase(id)
	_last_pos.erase(id)
	if world:
		world.remove_player(id)
	if was_playing:
		message.emit("%s left the game" % Net.get_player_name(id), COLOR_INFO)
	roles_changed.emit()
	scores_changed.emit()
	if Net.is_host():
		_check_round_over()


## A hider who picks the seeker team mid-round swaps sides straight away.
func on_team_preference_changed(id: int) -> void:
	if not Net.is_host() or world == null:
		return
	if roles.get(id) == "hider" and Net.players[id].get("team") == "seeker" and (phase == Phase.HIDING or phase == Phase.SEEKING):
		_catch(id, 0)


# --- Round broadcasts (host -> everyone) -------------------------------------

@rpc("authority", "call_local", "reliable")
func rpc_begin_round(num: int, new_roles: Dictionary, spawns: Dictionary, hide: float, new_scores: Dictionary) -> void:
	if world == null:
		return
	round_num = num
	roles = new_roles
	scores = new_scores
	hp.clear()
	disguises.clear()
	_cooldowns.clear()
	_charges.clear()
	world.clear_players()
	world.clear_round_objects()
	for id in roles:
		disguises[id] = ""
		hp[id] = max_hp_of(id)
		_charges[id] = BOLT_CHARGES
		world.spawn_player(id, roles[id], spawns[id])
	phase = Phase.HIDING
	time_left = hide
	_after_state_change()
	Sfx.play("round_start")
	if my_role() == "seeker":
		message.emit("Round %d: you are a SEEKER. Wait for the hiders..." % num, COLOR_BAD)
	else:
		message.emit("Round %d: you are a HIDER. Find a prop and blend in!" % num, COLOR_GOOD)


@rpc("authority", "call_local", "reliable")
func rpc_set_phase(new_phase: int, duration: float) -> void:
	phase = new_phase
	time_left = duration
	_after_state_change()
	if phase == Phase.SEEKING:
		Sfx.play("release")
		message.emit("The seekers are out!", COLOR_BAD)


@rpc("authority", "unreliable")
func rpc_sync_time(current_phase: int, remaining: float) -> void:
	if current_phase == phase:
		time_left = remaining


@rpc("authority", "call_local", "reliable")
func rpc_end_round(winner: String, new_scores: Dictionary) -> void:
	scores = new_scores
	phase = Phase.ROUND_END
	time_left = ROUND_END_TIME
	_after_state_change()
	Sfx.play("win")
	round_ended.emit(winner)


@rpc("authority", "call_local", "reliable")
func rpc_full_state(state: Dictionary) -> void:
	if world == null:
		return
	phase = state.phase
	time_left = state.time_left
	round_num = state.round
	roles = state.roles
	hp = state.hp
	disguises = state.disguises
	scores = state.scores
	world.clear_players()
	world.clear_round_objects()
	for id in roles:
		_charges[id] = BOLT_CHARGES
		var p = world.spawn_player(id, roles[id], state.positions.get(id, respawn_point(roles[id])))
		if disguises.get(id, "") != "":
			p.set_disguise(disguises[id])
	for decoy_id in state.decoys:
		var d: Array = state.decoys[decoy_id]
		world.spawn_decoy(decoy_id, d[0], d[1], d[2])
	_after_state_change()


@rpc("authority", "call_local", "reliable")
func rpc_add_player(id: int, role: String, pos: Vector3, new_scores: Dictionary) -> void:
	if world == null:
		return
	scores = new_scores
	roles[id] = role
	disguises[id] = ""
	hp[id] = max_hp_of(id)
	_charges[id] = BOLT_CHARGES
	if world.get_player(id) == null:
		world.spawn_player(id, role, pos)
	if id != my_id():
		message.emit("%s joined as a seeker" % Net.get_player_name(id), COLOR_INFO)
	_after_state_change()


@rpc("authority", "call_local", "reliable")
func rpc_message(text: String, color: Color) -> void:
	message.emit(text, color)


func _after_state_change() -> void:
	if world:
		for p in world.get_players():
			p.frozen = phase == Phase.HIDING and p.role == "seeker"
		_refresh_visibility()
	phase_changed.emit(phase)
	roles_changed.emit()
	scores_changed.emit()


## Seekers' names are public; hiders only see each other (and everyone at round
## end). Snares are only visible to seekers.
func _refresh_visibility() -> void:
	var mine := my_role()
	for p in world.get_players():
		p.name_tag.visible = not p.is_local and (p.role == "seeker" or mine == "hider" or phase == Phase.ROUND_END)
	world.set_traps_visible(mine == "seeker")


# --- Movement sync -----------------------------------------------------------

func send_state(pos: Vector3, yaw: float) -> void:
	if Net.is_host():
		_last_pos[my_id()] = pos
	rpc("rpc_state", pos, yaw)


@rpc("any_peer", "unreliable_ordered")
func rpc_state(pos: Vector3, yaw: float) -> void:
	var id := multiplayer.get_remote_sender_id()
	if Net.is_host():
		_last_pos[id] = pos
	var p := get_player(id)
	if p:
		p.apply_remote_state(pos, yaw)


func _broadcast_bots() -> void:
	var states := []
	for p in world.get_players():
		if p.is_bot:
			_last_pos[p.peer_id] = p.global_position
			states.append([p.peer_id, p.global_position, p.body_yaw])
	if not states.is_empty():
		rpc("rpc_bots_state", states)


@rpc("authority", "unreliable_ordered")
func rpc_bots_state(states: Array) -> void:
	for s in states:
		var p := get_player(s[0])
		if p:
			p.apply_remote_state(s[1], s[2])


# --- Seeker bolts ------------------------------------------------------------

func request_throw(origin: Vector3, direction: Vector3) -> void:
	if not _spend_charge(my_id()):
		return
	rpc_id(1, "rpc_request_throw", origin, direction)


## Bots throw from the host without the network round trip.
func bot_throw(id: int, origin: Vector3, direction: Vector3) -> bool:
	if not _spend_charge(id):
		return false
	_do_throw(id, origin, direction)
	return true


@rpc("any_peer", "call_local", "reliable")
func rpc_request_throw(origin: Vector3, direction: Vector3) -> void:
	if not Net.is_host():
		return
	var id := _sender()
	if id != my_id() and not _spend_charge(id):
		return  # The host already spent its own charge in request_throw.
	_do_throw(id, origin, direction)


func _spend_charge(id: int) -> bool:
	var charges: float = _charges.get(id, BOLT_CHARGES)
	if charges < 1.0:
		return false
	_charges[id] = charges - 1.0
	return true


func _do_throw(id: int, origin: Vector3, direction: Vector3) -> void:
	if phase != Phase.SEEKING or roles.get(id) != "seeker" or not _near_player(id, origin):
		return
	_spawn_projectile(id, origin, direction.normalized() * BOLT_SPEED, "bolt", BOLT_GRAVITY, BOLT_LIFE)


func _near_player(id: int, point: Vector3) -> bool:
	return not _last_pos.has(id) or (_last_pos[id] as Vector3).distance_to(point) < 4.0


func _spawn_projectile(owner_id: int, origin: Vector3, velocity: Vector3, kind: String, gravity: float, life: float) -> void:
	var pid := _next_projectile_id
	_next_projectile_id += 1
	_projectiles[pid] = {"owner": owner_id, "pos": origin, "vel": velocity, "kind": kind, "gravity": gravity, "life": life}
	rpc("rpc_bolt", pid, owner_id, origin, velocity, kind, gravity, life)


@rpc("authority", "call_local", "reliable")
func rpc_bolt(pid: int, owner_id: int, origin: Vector3, velocity: Vector3, kind: String, gravity: float, life: float) -> void:
	if world == null:
		return
	world.spawn_bolt(pid, origin, velocity, kind, gravity, life)
	var p := get_player(owner_id)
	if p:
		if owner_id != my_id():
			p.play_throw()
		Sfx.play_at("swing", origin, -8.0)


func _step_projectiles(delta: float) -> void:
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for pid in _projectiles.keys():
		var b: Dictionary = _projectiles[pid]
		b.life -= delta
		b.vel += Vector3.DOWN * b.gravity * delta
		var from: Vector3 = b.pos
		var to: Vector3 = from + b.vel * delta
		var exclude: Array[RID] = []
		var shooter := get_player(b.owner)
		if shooter:
			exclude.append(shooter.get_rid())
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, to, 1 | 2, exclude))
		if hit.is_empty():
			b.pos = to
			if b.life <= 0.0:
				_projectile_landed(pid, b, to, null)
			continue
		_projectile_landed(pid, b, hit.position, hit.collider)


func _projectile_landed(pid: int, b: Dictionary, pos: Vector3, collider: Object) -> void:
	_projectiles.erase(pid)
	rpc("rpc_bolt_end", pid, pos, collider != null)
	if b.kind == "flare":
		_flare_burst(b.owner, pos)
		return
	if collider == null:
		return
	if collider.has_meta("peer_id"):
		var target: int = collider.get_meta("peer_id")
		if roles.get(target) == "hider":
			_damage(target, BOLT_DAMAGE, b.owner)
	elif collider.has_meta("decoy_id"):
		_pop_decoy(collider.get_meta("decoy_id"), b.owner)


@rpc("authority", "call_local", "reliable")
func rpc_bolt_end(pid: int, pos: Vector3, burst: bool) -> void:
	if world:
		world.end_bolt(pid, pos, burst)
		if burst:
			Sfx.play_at("thud", pos, -6.0)


# --- Health ------------------------------------------------------------------

func _damage(target: int, amount: int, attacker: int) -> void:
	if phase != Phase.SEEKING or roles.get(target) != "hider":
		return
	_last_damage[target] = _now()
	var new_hp: int = hp.get(target, 0) - amount
	if new_hp > 0:
		rpc("rpc_hp", target, new_hp, attacker, true)
	else:
		_catch(target, attacker)


func _catch(target: int, catcher: int) -> void:
	if catcher != 0:
		scores[catcher] = scores.get(catcher, 0) + CATCH_POINTS
	var spawn := respawn_point("seeker")
	_last_pos[target] = spawn
	rpc("rpc_caught", target, catcher, spawn, scores)
	_check_round_over()


@rpc("authority", "call_local", "reliable")
func rpc_hp(target: int, value: int, attacker: int, was_hit: bool) -> void:
	hp[target] = value
	if not was_hit:
		return
	var p := get_player(target)
	if p:
		p.flash()
		Sfx.play_at("hit", p.global_position + Vector3.UP * 0.5)
	if target == my_id():
		Sfx.play("hurt")
		local_hit.emit(value)
	if attacker == my_id():
		hit_confirmed.emit()


@rpc("authority", "call_local", "reliable")
func rpc_caught(target: int, catcher: int, spawn: Vector3, new_scores: Dictionary) -> void:
	scores = new_scores
	roles[target] = "seeker"
	disguises[target] = ""
	hp[target] = max_hp_of(target)
	_charges[target] = BOLT_CHARGES
	var p := get_player(target)
	if p:
		world.puff(p.global_position + Vector3.UP * 0.5, p.color)
		Sfx.play_at("caught", p.global_position + Vector3.UP * 0.5, 4.0, 10.0)
		p.set_role("seeker")
		p.teleport(spawn)
	var target_name := Net.get_player_name(target)
	if catcher == 0:
		message.emit("%s joined the seekers" % target_name, COLOR_INFO)
	elif target == my_id():
		local_hit.emit(0)
		message.emit("You were found by %s! Now help them seek." % Net.get_player_name(catcher), COLOR_BAD)
	else:
		message.emit("%s found %s!" % [Net.get_player_name(catcher), target_name], COLOR_GOOD if my_role() == "seeker" else COLOR_BAD)
	if catcher == my_id():
		hit_confirmed.emit()
	_after_state_change()


# --- Disguises, taunts, decoys -----------------------------------------------

func request_disguise(prop: String) -> void:
	rpc_id(1, "rpc_request_disguise", prop)


func request_disguise_for(id: int, prop: String) -> void:
	if Net.is_host():
		_do_disguise(id, prop)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_disguise(prop: String) -> void:
	if Net.is_host():
		_do_disguise(_sender(), prop)


func _do_disguise(id: int, prop: String) -> void:
	if roles.get(id) != "hider" or not PropLib.PROPS.has(prop):
		return
	# Health keeps the same proportion when the disguise changes size.
	var ratio := float(hp.get(id, max_hp_of(id))) / max_hp_of(id)
	var new_hp := maxi(1, ceili(ratio * PropLib.max_hp_for(prop)))
	rpc("rpc_apply_disguise", id, prop, new_hp)


@rpc("authority", "call_local", "reliable")
func rpc_apply_disguise(id: int, prop: String, new_hp: int) -> void:
	disguises[id] = prop
	hp[id] = new_hp
	var p := get_player(id)
	if p:
		p.set_disguise(prop)
		world.puff(p.global_position + Vector3.UP * 0.4, Color(1, 1, 1))
		Sfx.play_at("poof", p.global_position, -4.0, 4.0)
	_refresh_visibility()


func request_taunt(index: int) -> void:
	rpc_id(1, "rpc_request_taunt", index)


func bot_taunt(id: int) -> void:
	if Net.is_host():
		_do_taunt(id, randi() % Sfx.TAUNT_COUNT)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_taunt(index: int) -> void:
	if Net.is_host():
		_do_taunt(_sender(), index)


func _do_taunt(id: int, index: int) -> void:
	if roles.get(id) != "hider" or cooldown_left(id, "taunt") > 0.3:
		return
	if phase == Phase.SEEKING:
		scores[id] = scores.get(id, 0) + TAUNT_POINTS
	rpc("rpc_play_taunt", id, clampi(index, 0, Sfx.TAUNT_COUNT - 1), scores, TAUNT_COOLDOWN)


@rpc("authority", "call_local", "reliable")
func rpc_play_taunt(id: int, index: int, new_scores: Dictionary, cooldown: float) -> void:
	scores = new_scores
	if cooldown > 0.0:
		_set_cooldown(id, "taunt", cooldown)
	var p := get_player(id)
	if p:
		p.bounce()
		Sfx.play_at("taunt%d" % index, p.global_position + Vector3.UP * 0.5, 6.0, 12.0)
	scores_changed.emit()


func _spawn_decoy(prop: String, pos: Vector3, yaw: float, owner_id: int) -> void:
	var decoy_id := _next_decoy_id
	_next_decoy_id += 1
	_decoys[decoy_id] = [prop, pos, yaw]
	rpc("rpc_spawn_decoy", decoy_id, prop, pos, yaw, owner_id)


@rpc("authority", "call_local", "reliable")
func rpc_spawn_decoy(decoy_id: int, prop: String, pos: Vector3, yaw: float, owner_id: int) -> void:
	if world == null:
		return
	var decoy: Node = world.spawn_decoy(decoy_id, prop, pos, yaw)
	var owner_player := get_player(owner_id)
	if owner_player and owner_player.controlled_here():
		# Let the owner walk out of a copy that appeared on top of them.
		owner_player.add_collision_exception_with(decoy)


func _pop_decoy(decoy_id: int, attacker: int) -> void:
	if _decoys.erase(decoy_id):
		rpc("rpc_remove_decoy", decoy_id, attacker)


@rpc("authority", "call_local", "reliable")
func rpc_remove_decoy(decoy_id: int, attacker: int) -> void:
	if world == null:
		return
	var pos = world.remove_decoy(decoy_id)
	if pos != null:
		world.puff(pos + Vector3.UP * 0.4, Color(0.9, 0.9, 0.9))
		Sfx.play_at("poof", pos)
	if attacker == my_id():
		message.emit("That was a decoy!", COLOR_BAD)


# --- Spells ------------------------------------------------------------------

## `id` is the caster: the local player, or a bot when called on the host.
func request_spell(id: int, slot: int, data: Dictionary) -> void:
	if id == my_id():
		rpc_id(1, "rpc_request_spell", slot, data)
	elif Net.is_host() and Net.is_bot(id):
		_do_spell(id, slot, data)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_spell(slot: int, data: Dictionary) -> void:
	if Net.is_host():
		_do_spell(_sender(), slot, data)


func _do_spell(id: int, slot: int, data: Dictionary) -> void:
	var spell := spell_in_slot(id, slot)
	if spell == "" or cooldown_left(id, spell) > 0.3 or roles.get(id) != Spells.SPELLS[spell].team:
		return
	if phase != Phase.SEEKING and not (phase == Phase.HIDING and roles[id] == "hider"):
		return
	var pos: Vector3 = _last_pos.get(id, Vector3.ZERO)
	var origin: Vector3 = data.get("origin", pos + Vector3.UP)
	var dir: Vector3 = (data.get("dir", Vector3.FORWARD) as Vector3).normalized()
	if not _near_player(id, origin):
		origin = pos + Vector3.UP * 1.5
	var extra := {"pos": pos}
	match spell:
		"decoy":
			var prop: String = disguises.get(id, "")
			if prop == "":
				_tell(id, "Mimic a prop first, then drop a decoy copy of it.")
				return
			_spawn_decoy(prop, pos, float(data.get("yaw", 0.0)), id)
		"blink":
			var move: Vector3 = data.get("move", Vector3.ZERO)
			extra.dir = move if Vector2(move.x, move.z).length() > 0.5 else dir
		"smoke", "haste":
			pass
		"echo":
			var target: Vector3 = data.get("target", pos)
			if target.distance_to(pos) > 45.0:
				target = pos + (target - pos).normalized() * 45.0
			extra.target = target
			extra.index = randi() % Sfx.TAUNT_COUNT
		"clutter":
			for i in 5:
				var a := randf() * TAU
				var spot := pos + Vector3(cos(a), 0, sin(a)) * randf_range(1.2, 3.0)
				_spawn_decoy(PropLib.SMALL.pick_random(), spot, randf() * TAU, id)
		"regrow":
			rpc("rpc_hp", id, mini(max_hp_of(id), hp.get(id, 0) + REGROW_HP), 0, false)
		"sonar":
			var found := []
			for other in roles:
				if roles[other] == "hider" and _last_pos.has(other) and pos.distance_to(_last_pos[other]) <= SONAR_RADIUS:
					found.append(other)
			extra.found = found
		"flare":
			_spawn_projectile(id, origin, dir * 22.0, "flare", 9.8, 3.0)
		"snare":
			_place_snare(id, pos)
		"scatter":
			if absf(dir.y) > 0.98:
				dir = Vector3(dir.x + 0.01, signf(dir.y) * 0.98, dir.z).normalized()
			var basis := Basis.looking_at(dir)
			for i in 5:
				var spread := basis * Vector3(randf_range(-0.12, 0.12), randf_range(-0.08, 0.08), -1.0)
				_spawn_projectile(id, origin, spread.normalized() * BOLT_SPEED, "bolt", BOLT_GRAVITY, BOLT_LIFE)
		"shockwave":
			for other in roles.keys():
				if roles.get(other) == "hider" and _last_pos.has(other) and pos.distance_to(_last_pos[other]) <= SHOCKWAVE_RADIUS:
					_damage(other, SHOCKWAVE_DAMAGE, id)
	rpc("rpc_spell_cast", id, spell, Spells.cooldown(spell), extra)


@rpc("authority", "call_local", "reliable")
func rpc_spell_cast(id: int, spell: String, cooldown: float, extra: Dictionary) -> void:
	_set_cooldown(id, spell, cooldown)
	if world == null:
		return
	var p := get_player(id)
	var pos: Vector3 = extra.get("pos", p.global_position if p else Vector3.ZERO)
	var mine := id == my_id()
	match spell:
		"blink":
			world.puff(pos + Vector3.UP * 0.5, Color(0.6, 1.0, 0.6), 14)
			if p and p.controlled_here():
				p.dash(extra.get("dir", Vector3.FORWARD))
		"smoke":
			world.smoke(pos, SMOKE_TIME)
			Sfx.play_at("poof", pos, 2.0)
		"echo":
			Sfx.play_at("taunt%d" % extra.get("index", 0), extra.get("target", pos), 6.0, 12.0)
		"clutter":
			Sfx.play_at("poof", pos)
		"regrow":
			world.puff(pos + Vector3.UP * 0.5, Color(0.5, 1.0, 0.5), 16)
		"sonar":
			world.wave(pos + Vector3.UP, SONAR_RADIUS, Color(0.4, 0.85, 1.0, 0.25))
			Sfx.play_at("sonar", pos + Vector3.UP)
			var found: Array = extra.get("found", [])
			get_tree().create_timer(0.6).timeout.connect(func():
				for hider in found:
					var h := get_player(hider)
					if h:
						Sfx.play_at("ping", h.global_position + Vector3.UP * 0.5, 2.0, 8.0)
			)
			if mine:
				message.emit("Sonar: nobody nearby." if found.is_empty() else "Sonar: %d hider(s) nearby! Listen for the pings." % found.size(), COLOR_INFO if found.is_empty() else COLOR_GOOD)
			elif my_id() in found:
				message.emit("A seeker's sonar pinged you!", COLOR_BAD)
		"haste":
			world.puff(pos + Vector3.UP * 0.3, Color(1.0, 0.9, 0.4), 12)
			if p and p.controlled_here():
				p.haste_timer = HASTE_TIME
		"shockwave":
			world.wave(pos + Vector3.UP * 0.5, SHOCKWAVE_RADIUS, Color(1.0, 0.6, 0.3, 0.35))
			Sfx.play_at("hit", pos, 2.0)


func _set_cooldown(id: int, key: String, duration: float) -> void:
	if not _cooldowns.has(id):
		_cooldowns[id] = {}
	_cooldowns[id][key] = _now() + duration


func _tell(id: int, text: String) -> void:
	if id == my_id():
		message.emit(text, COLOR_INFO)
	elif not Net.is_bot(id):
		rpc_id(id, "rpc_message", text, COLOR_INFO)


func _flare_burst(_owner_id: int, pos: Vector3) -> void:
	var found := []
	for id in roles:
		if roles[id] == "hider" and _last_pos.has(id) and pos.distance_to(_last_pos[id]) <= FLARE_RADIUS:
			found.append(id)
	rpc("rpc_reveal", found, REVEAL_TIME, pos)


@rpc("authority", "call_local", "reliable")
func rpc_reveal(ids: Array, duration: float, pos: Vector3) -> void:
	if world == null:
		return
	world.flash_light(pos, Color(1.0, 0.55, 0.25), 9.0)
	world.wave(pos, FLARE_RADIUS, Color(1.0, 0.55, 0.25, 0.3))
	Sfx.play_at("poof", pos, 2.0)
	for id in ids:
		var p := get_player(id)
		if p:
			p.reveal(duration)
	if my_id() in ids:
		message.emit("You've been marked by a flare! Move!", COLOR_BAD)


func _place_snare(owner_id: int, pos: Vector3) -> void:
	var mine := []
	for trap_id in _snares:
		if _snares[trap_id].owner == owner_id:
			mine.append(trap_id)
	while mine.size() >= MAX_SNARES:
		var oldest: int = mine.pop_front()
		_snares.erase(oldest)
		rpc("rpc_remove_snare", oldest)
	var trap_id := _next_snare_id
	_next_snare_id += 1
	_snares[trap_id] = {"pos": pos, "owner": owner_id}
	rpc("rpc_add_snare", trap_id, pos)


func _check_snares() -> void:
	if phase != Phase.SEEKING:
		return
	for trap_id in _snares.keys():
		var trap_pos: Vector3 = _snares[trap_id].pos
		for id in roles:
			if roles[id] != "hider" or not _last_pos.has(id):
				continue
			var p: Vector3 = _last_pos[id]
			if Vector2(p.x - trap_pos.x, p.z - trap_pos.z).length() < SNARE_RADIUS and absf(p.y - trap_pos.y) < 1.5:
				_snares.erase(trap_id)
				rpc("rpc_snared", id, trap_id)
				break


@rpc("authority", "call_local", "reliable")
func rpc_add_snare(trap_id: int, pos: Vector3) -> void:
	if world:
		world.add_trap(trap_id, pos, my_role() == "seeker")


@rpc("authority", "call_local", "reliable")
func rpc_remove_snare(trap_id: int) -> void:
	if world:
		world.remove_trap(trap_id)


@rpc("authority", "call_local", "reliable")
func rpc_snared(id: int, trap_id: int) -> void:
	if world == null:
		return
	world.remove_trap(trap_id)
	var p := get_player(id)
	if p:
		p.reveal(REVEAL_TIME)
		if p.controlled_here():
			p.root_timer = SNARE_ROOT
		Sfx.play_at("ping", p.global_position + Vector3.UP * 0.5, 4.0, 10.0)
		world.puff(p.global_position + Vector3.UP * 0.2, Color(1.0, 0.4, 0.3), 16)
	if id == my_id():
		message.emit("You stepped in a snare!", COLOR_BAD)
	elif my_role() == "seeker":
		message.emit("A snare caught %s!" % Net.get_player_name(id), COLOR_GOOD)


# --- Helpers -----------------------------------------------------------------

func _sender() -> int:
	var id := multiplayer.get_remote_sender_id()
	return id if id != 0 else multiplayer.get_unique_id()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _setup_input() -> void:
	_bind_keys("move_forward", [KEY_W, KEY_UP])
	_bind_keys("move_back", [KEY_S, KEY_DOWN])
	_bind_keys("move_left", [KEY_A, KEY_LEFT])
	_bind_keys("move_right", [KEY_D, KEY_RIGHT])
	_bind_keys("jump", [KEY_SPACE])
	_bind_keys("sprint", [KEY_SHIFT])
	_bind_keys("mimic", [KEY_E])
	_bind_keys("lock_rotation", [KEY_R])
	_bind_keys("taunt", [KEY_T])
	_bind_keys("spell1", [KEY_Q])
	_bind_keys("spell2", [KEY_F])
	_bind_mouse("throw", MOUSE_BUTTON_LEFT)
	_bind_keys("scoreboard", [KEY_TAB])
	_bind_keys("pause", [KEY_ESCAPE])


## Physical keys, so WASD sits in the same place on AZERTY (ZQSD) keyboards.
func _bind_keys(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for key in keys:
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func _bind_mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var event := InputEventMouseButton.new()
	event.button_index = button
	InputMap.action_add_event(action, event)
