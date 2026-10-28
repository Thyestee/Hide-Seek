extends Node
## Test-only autopilot, enabled with `-- --bot`. It drives the local player
## through the same network requests real input uses, so several headless
## copies can play a full round on their own.

var _timer := 0.0
var _did_disguise := false
var _did_decoy := false


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0 or not Game.in_game():
		return
	_timer = 0.5
	var me: Node3D = Game.local_player()
	if me == null:
		return
	if Game.phase == Game.Phase.ROUND_END:
		_did_disguise = false
		_did_decoy = false
		return
	if Game.my_role() == "hider":
		if not _did_disguise:
			_did_disguise = true
			Game.request_disguise("barrel")
		elif not _did_decoy and me.disguise != "":
			_did_decoy = true
			Game.request_decoy(me.global_position + Vector3(2, 0, 0), 0.0)
		elif randf() < 0.2:
			Game.request_taunt(randi() % Sfx.TAUNT_COUNT)
	elif Game.phase == Game.Phase.SEEKING:
		Game.request_sonar()
		var target := _nearest_hider(me)
		if target:
			# Walk up to the hider (teleport, we're a test) and bonk it.
			me.teleport(target.global_position + Vector3(1.5, 0, 0))
			Game.send_state(me.global_position, 0.0)
			Game.request_hit(target.peer_id)


func _nearest_hider(me: Node3D) -> Node3D:
	var best: Node3D = null
	for p in Game.world.get_players():
		if p.role == "hider" and (best == null or me.global_position.distance_to(p.global_position) < me.global_position.distance_to(best.global_position)):
			best = p
	return best


func _ready() -> void:
	Game.message.connect(func(text, _color): print("[%s] %s" % [Net.player_name, text]))
