extends Node
## Round logic. The host is the authority: clients send requests, the host
## checks them and broadcasts the result to everyone (itself included).
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

const MAX_HP := 100
const HIT_DAMAGE := 34
const HIT_RANGE := 5.0
const DECOYS_PER_ROUND := 2
const ROUND_END_TIME := 10.0
const FORCED_TAUNT_WINDOW := 60.0
const FORCED_TAUNT_INTERVAL := 20.0
const SONAR_RADIUS := 14.0
const SONAR_COOLDOWN := 20.0
const TAUNT_COOLDOWN := 6.0
const SEEKER_RATIO := 0.2
const CATCH_POINTS := 100
const SURVIVE_POINTS := 200
const TAUNT_POINTS := 10

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
var decoys_left := 0 # for the local player
var world: Node3D = null

# Host-only bookkeeping.
var _last_pos := {}
var _decoys_left := {}
var _decoys := {}  # decoy id -> [prop, position, yaw]
var _next_decoy_id := 1
var _seeker_history := {}
var _last_taunt := {}
var _last_sonar := {}
var _solo_round := false
var _sync_timer := 0.0
var _forced_taunt_timer := 0.0
var _key_labels := {}


func _ready() -> void:
	_setup_input()


func _process(delta: float) -> void:
	if world == null or phase == Phase.LOBBY:
		return
	time_left = maxf(time_left - delta, 0.0)
	if not Net.is_host():
		return
	_sync_timer += delta
	if _sync_timer >= 2.0:
		_sync_timer = 0.0
		rpc("rpc_sync_time", phase, time_left)
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


func respawn_point(role: String) -> Vector3:
	var points: Array = world.seeker_spawns if role == "seeker" else world.hider_spawns
	return points.pick_random() + Vector3(randf_range(-0.6, 0.6), 0.0, randf_range(-0.6, 0.6))


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
	_start_round()


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
	_last_pos.clear()
	_decoys.clear()
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
		_decoys_left[id] = DECOYS_PER_ROUND
		_last_pos[id] = spawns[id]
	_decoys.clear()
	_forced_taunt_timer = 0.0
	_sync_timer = 0.0
	rpc("rpc_begin_round", round_num, new_roles, spawns, hide_time, scores)


func _pick_seekers(ids: Array) -> Array:
	if ids.size() == 1:
		return []  # Practice round: a lone player explores as a hider.
	var count := clampi(roundi(ids.size() * SEEKER_RATIO), 1, ids.size() - 1)
	var pool := ids.duplicate()
	pool.shuffle()
	# Players who have been seeker the least go first.
	pool.sort_custom(func(a, b): return _seeker_history.get(a, 0) < _seeker_history.get(b, 0))
	var picked := pool.slice(0, count)
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
			rpc("rpc_play_taunt", id, randi() % Sfx.TAUNT_COUNT, scores)
	if any:
		rpc("rpc_message", "The hiders can't keep quiet any more...", COLOR_INFO)


## Called by Net once a newly connected peer has told us its name.
func on_player_registered(id: int) -> void:
	scores[id] = scores.get(id, 0)
	if world == null:
		return
	# Late joiners help seek, so they're never stuck waiting for the next round.
	var spawn := respawn_point("seeker")
	roles[id] = "seeker"
	hp[id] = MAX_HP
	disguises[id] = ""
	_decoys_left[id] = 0
	_last_pos[id] = spawn
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
	world.clear_players()
	world.clear_decoys()
	for id in roles:
		hp[id] = MAX_HP
		disguises[id] = ""
		world.spawn_player(id, roles[id], spawns[id])
	decoys_left = DECOYS_PER_ROUND
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
	decoys_left = 0
	world.clear_players()
	world.clear_decoys()
	for id in roles:
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
	hp[id] = MAX_HP
	disguises[id] = ""
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
		_refresh_name_tags()
	phase_changed.emit(phase)
	roles_changed.emit()
	scores_changed.emit()


## Seekers' names are public; hiders only see each other (and everyone at round end).
func _refresh_name_tags() -> void:
	var mine := my_role()
	for p in world.get_players():
		p.name_tag.visible = not p.is_local and (p.role == "seeker" or mine == "hider" or phase == Phase.ROUND_END)


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


# --- Seeker actions ----------------------------------------------------------

func broadcast_swing() -> void:
	rpc("rpc_swing")


@rpc("any_peer", "unreliable")
func rpc_swing() -> void:
	var p := get_player(multiplayer.get_remote_sender_id())
	if p:
		p.play_swing()
		Sfx.play_at("swing", p.global_position + Vector3.UP, -6.0)


func request_hit(target: int) -> void:
	rpc_id(1, "rpc_request_hit", target)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_hit(target: int) -> void:
	if not Net.is_host() or phase != Phase.SEEKING:
		return
	var attacker := _sender()
	if roles.get(attacker) != "seeker" or roles.get(target) != "hider":
		return
	if _last_pos.has(attacker) and _last_pos.has(target):
		if (_last_pos[attacker] as Vector3).distance_to(_last_pos[target]) > HIT_RANGE:
			return
	var new_hp: int = hp.get(target, MAX_HP) - HIT_DAMAGE
	if new_hp > 0:
		rpc("rpc_hp", target, new_hp, attacker)
		return
	scores[attacker] = scores.get(attacker, 0) + CATCH_POINTS
	var spawn := respawn_point("seeker")
	_last_pos[target] = spawn
	rpc("rpc_caught", target, attacker, spawn, scores)
	_check_round_over()


@rpc("authority", "call_local", "reliable")
func rpc_hp(target: int, value: int, attacker: int) -> void:
	hp[target] = value
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
	hp[target] = MAX_HP
	disguises[target] = ""
	var p := get_player(target)
	if p:
		world.puff(p.global_position + Vector3.UP * 0.5, p.color)
		Sfx.play_at("caught", p.global_position + Vector3.UP * 0.5, 4.0, 10.0)
		p.set_role("seeker")
		p.teleport(spawn)
	var text := "%s found %s!" % [Net.get_player_name(catcher), Net.get_player_name(target)]
	if target == my_id():
		local_hit.emit(0)
		message.emit("You were found by %s! Now help them seek." % Net.get_player_name(catcher), COLOR_BAD)
	else:
		message.emit(text, COLOR_GOOD if my_role() == "seeker" else COLOR_BAD)
	if catcher == my_id():
		hit_confirmed.emit()
	_after_state_change()


func request_decoy_hit(decoy_id: int) -> void:
	rpc_id(1, "rpc_request_decoy_hit", decoy_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_decoy_hit(decoy_id: int) -> void:
	if not Net.is_host() or phase != Phase.SEEKING:
		return
	var attacker := _sender()
	if roles.get(attacker) != "seeker" or not _decoys.has(decoy_id):
		return
	_decoys.erase(decoy_id)
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


func request_sonar() -> void:
	rpc_id(1, "rpc_request_sonar")


@rpc("any_peer", "call_local", "reliable")
func rpc_request_sonar() -> void:
	if not Net.is_host() or phase != Phase.SEEKING:
		return
	var id := _sender()
	if roles.get(id) != "seeker" or not _last_pos.has(id):
		return
	if _now() - _last_sonar.get(id, -1000.0) < SONAR_COOLDOWN - 1.0:
		return
	_last_sonar[id] = _now()
	var origin: Vector3 = _last_pos[id]
	var found := []
	for other in roles:
		if roles[other] == "hider" and _last_pos.has(other) and origin.distance_to(_last_pos[other]) <= SONAR_RADIUS:
			found.append(other)
	rpc("rpc_sonar", id, origin, found)


@rpc("authority", "call_local", "reliable")
func rpc_sonar(seeker: int, origin: Vector3, found: Array) -> void:
	if world == null:
		return
	world.sonar_wave(origin + Vector3.UP, SONAR_RADIUS)
	Sfx.play_at("sonar", origin + Vector3.UP)
	get_tree().create_timer(0.6).timeout.connect(func():
		for id in found:
			var p := get_player(id)
			if p:
				Sfx.play_at("ping", p.global_position + Vector3.UP * 0.5, 2.0, 8.0)
	)
	if seeker == my_id():
		if found.is_empty():
			message.emit("Sonar: nobody nearby.", COLOR_INFO)
		else:
			message.emit("Sonar: %d hider(s) nearby! Listen for the pings." % found.size(), COLOR_GOOD)
	elif my_id() in found:
		message.emit("A seeker's sonar pinged you!", COLOR_BAD)


# --- Hider actions -----------------------------------------------------------

func request_disguise(prop: String) -> void:
	rpc_id(1, "rpc_request_disguise", prop)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_disguise(prop: String) -> void:
	if not Net.is_host():
		return
	var id := _sender()
	if roles.get(id) == "hider" and PropLib.PROPS.has(prop):
		rpc("rpc_apply_disguise", id, prop)


@rpc("authority", "call_local", "reliable")
func rpc_apply_disguise(id: int, prop: String) -> void:
	disguises[id] = prop
	var p := get_player(id)
	if p:
		p.set_disguise(prop)
		world.puff(p.global_position + Vector3.UP * 0.4, Color(1, 1, 1))
		Sfx.play_at("poof", p.global_position, -4.0, 4.0)
	_refresh_name_tags()


func request_taunt(index: int) -> void:
	rpc_id(1, "rpc_request_taunt", index)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_taunt(index: int) -> void:
	if not Net.is_host():
		return
	var id := _sender()
	if roles.get(id) != "hider" or _now() - _last_taunt.get(id, -1000.0) < TAUNT_COOLDOWN - 0.5:
		return
	_last_taunt[id] = _now()
	if phase == Phase.SEEKING:
		scores[id] = scores.get(id, 0) + TAUNT_POINTS
	rpc("rpc_play_taunt", id, clampi(index, 0, Sfx.TAUNT_COUNT - 1), scores)


@rpc("authority", "call_local", "reliable")
func rpc_play_taunt(id: int, index: int, new_scores: Dictionary) -> void:
	scores = new_scores
	var p := get_player(id)
	if p:
		p.bounce()
		Sfx.play_at("taunt%d" % index, p.global_position + Vector3.UP * 0.5, 6.0, 12.0)
	scores_changed.emit()


func request_decoy(pos: Vector3, yaw: float) -> void:
	rpc_id(1, "rpc_request_decoy", pos, yaw)


@rpc("any_peer", "call_local", "reliable")
func rpc_request_decoy(pos: Vector3, yaw: float) -> void:
	if not Net.is_host() or (phase != Phase.HIDING and phase != Phase.SEEKING):
		return
	var id := _sender()
	var prop: String = disguises.get(id, "")
	if roles.get(id) != "hider" or prop == "" or _decoys_left.get(id, 0) <= 0:
		return
	_decoys_left[id] -= 1
	var decoy_id := _next_decoy_id
	_next_decoy_id += 1
	_decoys[decoy_id] = [prop, pos, yaw]
	rpc("rpc_spawn_decoy", decoy_id, prop, pos, yaw, id, _decoys_left[id])


@rpc("authority", "call_local", "reliable")
func rpc_spawn_decoy(decoy_id: int, prop: String, pos: Vector3, yaw: float, owner_id: int, remaining: int) -> void:
	if world == null:
		return
	var decoy: Node = world.spawn_decoy(decoy_id, prop, pos, yaw)
	if owner_id == my_id():
		decoys_left = remaining
		var me := local_player()
		if me:
			# Let the owner walk out of the copy that just appeared on top of them.
			me.add_collision_exception_with(decoy)
		message.emit("Decoy placed (%d left)" % remaining, COLOR_GOOD)


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
	_bind_keys("taunt", [KEY_F])
	_bind_keys("decoy", [KEY_G])
	_bind_keys("sonar", [KEY_Q])
	_bind_mouse("swing", MOUSE_BUTTON_LEFT)
	_bind_mouse("sonar", MOUSE_BUTTON_RIGHT)
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
