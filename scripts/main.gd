extends Node
## Owns the menu and the HUD and switches between them.
##
## Command-line helpers (after `--`), handy for testing several copies at once:
##   --name=Bob  --host  --join=192.168.1.20  --autostart=N (host starts at N players)
##   --screenshot=path.png  (saves a screenshot a few seconds into the game, then quits)
##   --quit-after-round  (quits once the first round is over)
##   --bots=N  (host adds N AI bots)  --team=hider|seeker|auto  --log (print game messages)

const MenuScript = preload("res://scripts/ui/menu.gd")
const HudScript = preload("res://scripts/ui/hud.gd")
const UiTheme = preload("res://scripts/ui/ui_theme.gd")

var menu: Control
var hud: CanvasLayer
var _args := {}


func _ready() -> void:
	var theme := UiTheme.build()
	var menu_layer := CanvasLayer.new()
	add_child(menu_layer)
	menu = MenuScript.new()
	menu.theme = theme
	menu_layer.add_child(menu)
	hud = HudScript.new()
	hud.ui_theme = theme
	hud.visible = false
	add_child(hud)
	Game.entered_game.connect(_on_entered_game)
	Game.left_game.connect(_on_left_game)
	Net.connection_closed.connect(_on_connection_closed)
	_handle_args()


func _on_entered_game() -> void:
	menu.visible = false
	hud.visible = true
	hud.on_game_started()


func _on_left_game() -> void:
	hud.visible = false
	menu.visible = true
	if Net.online:
		menu.show_lobby()


func _on_connection_closed(reason: String) -> void:
	hud.visible = false
	menu.visible = true
	menu.show_main(reason)


# --- Testing helpers ---------------------------------------------------------

func _handle_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var parts: PackedStringArray = arg.trim_prefix("--").split("=", true, 1)
		_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	if _args.has("name"):
		Net.player_name = _args.name
	if _args.has("team"):
		Net.team_preference = _args.team
	if _args.has("log"):
		Game.message.connect(func(text, _color): print("[%s] %s" % [Net.player_name, text]))
	if _args.has("host"):
		Net.host_game()
		menu.show_lobby()
		for i in int(_args.get("bots", "0")):
			Net.add_bot()
	elif _args.has("join"):
		Net.join_game(_args.join)
	if _args.has("autostart"):
		Net.players_changed.connect(func():
			if Net.is_host() and not Game.in_game() and Net.players.size() >= int(_args.autostart):
				Game.host_start_game.call_deferred(float(_args.get("hide", "40")), float(_args.get("seek", "240")))
		)
		Net.players_changed.emit()
	if _args.has("screenshot"):
		if _args.has("autostart") or _args.has("join"):
			Game.entered_game.connect(_take_screenshot)
		else:
			_take_screenshot()
	if _args.has("quit-after-round"):
		Game.round_ended.connect(func(winner):
			print("Round over, winner: ", winner)
			get_tree().create_timer(1.0).timeout.connect(get_tree().quit)
		)


func _take_screenshot() -> void:
	await get_tree().create_timer(float(_args.get("shot_delay", "4"))).timeout
	get_viewport().get_texture().get_image().save_png(_args.screenshot)
	print("Saved screenshot to ", _args.screenshot)
	get_tree().quit()
