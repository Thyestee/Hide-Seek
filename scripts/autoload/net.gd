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
const COLORS := [
	Color(0.95, 0.33, 0.30), Color(0.30, 0.60, 0.95), Color(0.35, 0.80, 0.35),
	Color(0.98, 0.80, 0.25), Color(0.75, 0.40, 0.90), Color(0.98, 0.55, 0.20),
	Color(0.30, 0.85, 0.85), Color(0.95, 0.45, 0.70), Color(0.60, 0.85, 0.30),
	Color(0.92, 0.92, 0.92), Color(0.25, 0.38, 0.75), Color(0.75, 0.22, 0.32),
	Color(0.40, 0.72, 0.60), Color(0.88, 0.72, 0.55), Color(0.55, 0.50, 0.95),
	Color(0.95, 0.95, 0.50), Color(0.62, 0.35, 0.18), Color(0.40, 0.40, 0.42),
	Color(0.85, 0.55, 0.55), Color(0.20, 0.55, 0.35),
]

var players := {}  # peer id -> {"name": String, "color": Color}
var player_name := ""
var last_ip := "127.0.0.1"
var mouse_sensitivity := 1.0
var online := false
var found_hosts := {}  # ip -> info dictionary from the host's broadcast

var _broadcaster: PacketPeerUDP
var _listener: PacketPeerUDP
var _broadcast_timer := 0.0


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
				"max": MAX_PLAYERS, "in_game": Game.in_game(),
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
	players = {1: {"name": player_name, "color": COLORS[0]}}
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


func _on_connected() -> void:
	rpc_id(1, "rpc_register", player_name)
	connected_to_host.emit()


func _on_connection_failed() -> void:
	leave("Could not reach the host.")


func _on_server_disconnected() -> void:
	leave("The host closed the game.")


func _on_peer_disconnected(id: int) -> void:
	if is_host():
		players.erase(id)
		rpc("rpc_sync_players", players)
	Game.on_peer_left(id)


@rpc("any_peer", "reliable")
func rpc_register(requested_name: String) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if players.size() >= MAX_PLAYERS:
		multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	players[id] = {"name": _unique_name(requested_name), "color": _free_color()}
	rpc("rpc_sync_players", players)
	Game.on_player_registered(id)


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


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "last_ip", last_ip)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.save(SETTINGS_PATH)
