extends Node
## Connections, the lobby player list, local settings and LAN discovery.
## The host is peer 1 and also plays; everyone else joins it over ENet.

signal players_changed
signal connected_to_host
signal connection_closed(reason: String)
signal hosts_changed

const PORT := 7777
const DISCOVERY_PORT := 7778
const MAX_PLAYERS := 20
const GAME_TAG := "hide-seek"
const SETTINGS_PATH := "user://settings.cfg"
const Spells = preload("res://scripts/spells.gd")
const TEAMS := ["auto", "hider", "seeker"]
const BOT_NAMES := [
	"Pip", "Moss", "Tumble", "Fern", "Biscuit", "Nib", "Wobble", "Clover", "Pebble", "Sprout",
	"Bramble", "Dot", "Puddle", "Acorn", "Waffle", "Thimble", "Sorrel", "Nutmeg", "Twig", "Juniper",
]
const COLORS := [
	Color(0.95, 0.33, 0.30), Color(0.30, 0.60, 0.95), Color(0.35, 0.80, 0.35),
	Color(0.98, 0.80, 0.25), Color(0.75, 0.40, 0.90), Color(0.98, 0.55, 0.20),
	Color(0.30, 0.85, 0.85), Color(0.95, 0.45, 0.70), Color(0.60, 0.85, 0.30),
	Color(0.92, 0.92, 0.92), Color(0.25, 0.38, 0.75), Color(0.75, 0.22, 0.32),
	Color(0.40, 0.72, 0.60), Color(0.88, 0.72, 0.55), Color(0.55, 0.50, 0.95),
	Color(0.95, 0.95, 0.50), Color(0.62, 0.35, 0.18), Color(0.40, 0.40, 0.42),
	Color(0.85, 0.55, 0.55), Color(0.20, 0.55, 0.35),
]

var players := {}  # peer id -> {name, color, team, loadout, bot}; bots have negative ids
var player_name := ""
var last_ip := "127.0.0.1"
var mouse_sensitivity := 1.0
var team_preference := "auto"
var loadout: Dictionary = Spells.DEFAULT_LOADOUT.duplicate(true)
var online := false
var found_hosts := {}  # ip -> info dictionary from the host's broadcast

var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer := 0.0
var _rejection := ""  # why the host turned us away, shown after the disconnect
var _next_bot_id := -1


func _ready() -> void:
	_load_settings()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func _process(delta: float) -> void:
	if _broadcaster:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = 1.0
			var info := {
				"game": GAME_TAG, "name": player_name, "players": players.size(),
				"max": MAX_PLAYERS, "in_game": Game.in_game(), "version": game_version(),
			}
			_broadcaster.put_packet(JSON.stringify(info).to_utf8_buffer())
	if _listener:
		_poll_discovery()


# --- Hosting and joining -----------------------------------------------------

func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	players = {1: _entry(player_name, COLORS[0], team_preference, loadout, false)}
	stop_discovery()
	_broadcaster = PacketPeerUDP.new()
	_broadcaster.set_broadcast_enabled(true)
	_broadcaster.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	_broadcast_timer = 0.0
	save_settings()
	players_changed.emit()
	return OK


func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	online = true
	last_ip = ip
	save_settings()
	return OK


func leave(reason := "") -> void:
	if _broadcaster:
		_broadcaster.close()
		_broadcaster = null
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	online = false
	players.clear()
	Game.reset()
	if reason != "":
		print("[net] ", reason)
	connection_closed.emit(reason)


func is_host() -> bool:
	return online and multiplayer.is_server()


func get_player_name(id: int) -> String:
	return players.get(id, {}).get("name", "Player %d" % id)


func get_player_color(id: int) -> Color:
	return players.get(id, {}).get("color", Color.WHITE)


func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address.count(".") == 3 and not address.begins_with("127.") and not address.begins_with("169.254."):
			out.append(address)
	return out


func game_version() -> String:
	return ProjectSettings.get_setting("application/config/version", "dev")


func _on_connected() -> void:
	_rejection = ""
	rpc_id(1, "rpc_register", player_name, game_version(), team_preference, loadout)
	connected_to_host.emit()


func _on_connection_failed() -> void:
	leave("Could not reach the host.")


func _on_server_disconnected() -> void:
	leave(_rejection if _rejection != "" else "The host closed the game.")


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		players.erase(id)
		rpc("rpc_sync_players", players)
	Game.on_peer_left(id)


@rpc("any_peer", "reliable")
func rpc_register(requested_name: String, version: String, team: String, picks: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if version != game_version():
		# Different builds don't speak the same network protocol.
		_reject(id, "The host runs version %s but you have %s. Update the game with the launcher." % [game_version(), version])
		return
	if players.size() >= MAX_PLAYERS:
		_reject(id, "The game is full (%d players)." % MAX_PLAYERS)
		return
	players[id] = _entry(_unique_name(requested_name), _free_color(), team, picks, false)
	rpc("rpc_sync_players", players)
	Game.on_player_registered(id)


func _entry(player_name_: String, color: Color, team: String, picks, bot: bool) -> Dictionary:
	return {
		"name": player_name_, "color": color, "team": team if team in TEAMS else "auto",
		"loadout": Spells.sanitize(picks), "bot": bot,
	}


func is_bot(id: int) -> bool:
	return players.get(id, {}).get("bot", false)


func bot_count() -> int:
	var n := 0
	for id in players:
		if is_bot(id):
			n += 1
	return n


## Saves this player's team and spells and tells the host.
func set_preferences(team: String, picks: Dictionary) -> void:
	team_preference = team
	loadout = Spells.sanitize(picks)
	save_settings()
	if online and players.has(multiplayer.get_unique_id()):
		rpc_id(1, "rpc_set_prefs", team_preference, loadout)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_prefs(team: String, picks: Dictionary) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = multiplayer.get_unique_id()
	if not players.has(id):
		return
	players[id].team = team if team in TEAMS else "auto"
	players[id].loadout = Spells.sanitize(picks)
	rpc("rpc_sync_players", players)
	Game.on_team_preference_changed(id)


# --- Bots (host only) --------------------------------------------------------

func add_bot() -> void:
	if not is_host() or players.size() >= MAX_PLAYERS:
		return
	var id := _next_bot_id
	_next_bot_id -= 1
	var taken := []
	for info in players.values():
		taken.append(info.name)
	var bot_name := ""
	for candidate in BOT_NAMES:
		if not "Bot %s" % candidate in taken:
			bot_name = "Bot %s" % candidate
			break
	if bot_name == "":
		bot_name = _unique_name("Bot")
	players[id] = _entry(bot_name, _free_color(), "auto", Spells.random_loadout(), true)
	rpc("rpc_sync_players", players)
	Game.on_player_registered(id)


func remove_bot() -> void:
	if not is_host():
		return
	var bots := []
	for id in players:
		if is_bot(id):
			bots.append(id)
	if bots.is_empty():
		return
	bots.sort()  # newest bot has the lowest id
	var id: int = bots[0]
	players.erase(id)
	rpc("rpc_sync_players", players)
	rpc("rpc_bot_left", id)


@rpc("authority", "call_local", "reliable")
func rpc_bot_left(id: int) -> void:
	Game.on_peer_left(id)


func _reject(id: int, reason: String) -> void:
	rpc_id(id, "rpc_rejected", reason)
	get_tree().create_timer(0.5).timeout.connect(func():
		if multiplayer.multiplayer_peer:
			multiplayer.multiplayer_peer.disconnect_peer(id)
	)


@rpc("authority", "reliable")
func rpc_rejected(reason: String) -> void:
	_rejection = reason


@rpc("authority", "call_local", "reliable")
func rpc_sync_players(list: Dictionary) -> void:
	players = list
	players_changed.emit()


func _unique_name(requested: String) -> String:
	var base := requested.strip_edges().left(16)
	if base.is_empty():
		base = "Player"
	var taken := []
	for info in players.values():
		taken.append(info.name)
	var candidate := base
	var n := 2
	while candidate in taken:
		candidate = "%s %d" % [base, n]
		n += 1
	return candidate


func _free_color() -> Color:
	var used := []
	for info in players.values():
		used.append(info.color)
	for c in COLORS:
		if not c in used:
			return c
	return Color.from_hsv(randf(), 0.6, 0.9)


# --- LAN discovery -----------------------------------------------------------

func start_discovery() -> void:
	if _listener:
		return
	_listener = PacketPeerUDP.new()
	if _listener.bind(DISCOVERY_PORT) != OK:
		# Another copy of the game on this PC already listens; manual IP still works.
		_listener = null


func stop_discovery() -> void:
	if _listener:
		_listener.close()
		_listener = null
	found_hosts.clear()
	hosts_changed.emit()


func _poll_discovery() -> void:
	var changed := false
	while _listener.get_available_packet_count() > 0:
		var packet := _listener.get_packet()
		var ip := _listener.get_packet_ip()
		var data = JSON.parse_string(packet.get_string_from_utf8())
		if data is Dictionary and data.get("game") == GAME_TAG:
			data["seen"] = Time.get_ticks_msec()
			found_hosts[ip] = data
			changed = true
	for ip in found_hosts.keys():
		if Time.get_ticks_msec() - found_hosts[ip].seen > 3500:
			found_hosts.erase(ip)
			changed = true
	if changed:
		hosts_changed.emit()


# --- Settings ----------------------------------------------------------------

func _load_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var default_name := OS.get_environment("USERNAME")
	if default_name.is_empty():
		default_name = "Player %d" % (randi() % 1000)
	player_name = cfg.get_value("player", "name", default_name)
	last_ip = cfg.get_value("player", "last_ip", last_ip)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	team_preference = cfg.get_value("player", "team", team_preference)
	loadout = Spells.sanitize(cfg.get_value("player", "loadout", loadout))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.set_value("player", "team", team_preference)
	cfg.set_value("player", "loadout", loadout)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.save(SETTINGS_PATH)
