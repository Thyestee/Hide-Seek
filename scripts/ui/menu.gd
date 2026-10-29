extends Control
## Title screen (host / join / LAN browser) and the lobby.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const LoadoutPanel = preload("res://scripts/ui/loadout_panel.gd")

var _main_page: Control
var _lobby_page: Control
var _name_edit: LineEdit
var _ip_edit: LineEdit
var _status: Label
var _hosts_box: VBoxContainer
var _players_title: Label
var _players_box: VBoxContainer
var _address_label: Label
var _host_settings: Control
var _hide_spin: SpinBox
var _seek_spin: SpinBox
var _start_button: Button
var _waiting_label: Label
var _bot_buttons: HBoxContainer
var _loadout: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.2, 0.17)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_add_backdrop_blobs()
	var version := UiTheme.label("Version %s" % Net.game_version(), 16, UiTheme.MUTED)
	version.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	version.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	version.grow_vertical = Control.GROW_DIRECTION_BEGIN
	version.offset_right = -16
	version.offset_bottom = -10
	add_child(version)
	_main_page = _build_main_page()
	_lobby_page = _build_lobby_page()
	Net.players_changed.connect(_refresh_lobby)
	Net.hosts_changed.connect(_refresh_hosts)
	Net.connected_to_host.connect(show_lobby)
	show_main()


func show_main(message := "") -> void:
	_main_page.visible = true
	_lobby_page.visible = false
	_status.text = message
	Net.start_discovery()
	_refresh_hosts()


func show_lobby() -> void:
	_main_page.visible = false
	_lobby_page.visible = true
	Net.stop_discovery()
	_refresh_lobby()


# --- Title page --------------------------------------------------------------

func _build_main_page() -> Control:
	var page := _centered_panel(560)
	var box: VBoxContainer = page.get_meta("box")
	var title := UiTheme.outlined("HIDE & SEEK", 64, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var subtitle := UiTheme.label("Become the furniture. Bonk the furniture.", 20, UiTheme.MUTED)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(subtitle)
	box.add_child(_spacer(10))

	box.add_child(UiTheme.label("Your name", 16, UiTheme.MUTED))
	_name_edit = LineEdit.new()
	_name_edit.text = Net.player_name
	_name_edit.max_length = 16
	_name_edit.text_changed.connect(func(t): Net.player_name = t.strip_edges())
	box.add_child(_name_edit)
	box.add_child(_spacer(6))

	var host := Button.new()
	host.text = "Host a game"
	host.pressed.connect(_on_host)
	box.add_child(host)

	var join_row := HBoxContainer.new()
	join_row.add_theme_constant_override("separation", 8)
	_ip_edit = LineEdit.new()
	_ip_edit.text = Net.last_ip
	_ip_edit.placeholder_text = "Host IP, e.g. 192.168.1.20"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_ip_edit.text_submitted.connect(func(_t): _on_join(_ip_edit.text))
	join_row.add_child(_ip_edit)
	var join := Button.new()
	join.text = "Join"
	join.pressed.connect(func(): _on_join(_ip_edit.text))
	join_row.add_child(join)
	box.add_child(join_row)

	box.add_child(_spacer(6))
	box.add_child(UiTheme.label("Games on your network", 16, UiTheme.MUTED))
	_hosts_box = VBoxContainer.new()
	box.add_child(_hosts_box)

	_status = UiTheme.label("", 18, Color(1, 0.6, 0.5))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)

	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)
	return page


func _refresh_hosts() -> void:
	if _hosts_box == null:
		return
	for c in _hosts_box.get_children():
		c.queue_free()
	if Net.found_hosts.is_empty():
		_hosts_box.add_child(UiTheme.label("Looking for games...", 17, UiTheme.MUTED.darkened(0.2)))
		return
	for ip in Net.found_hosts:
		var info: Dictionary = Net.found_hosts[ip]
		var b := Button.new()
		var state := "in game" if info.get("in_game", false) else "in lobby"
		b.text = "%s's game  -  %d/%d players, %s  (%s)" % [info.get("name", "?"), info.get("players", 0), info.get("max", 20), state, ip]
		var host_version: String = info.get("version", "?")
		if host_version != Net.game_version():
			b.text += "  -  needs version %s" % host_version
			b.disabled = true
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): _on_join(ip))
		_hosts_box.add_child(b)


func _on_host() -> void:
	if not _check_name():
		return
	var err := Net.host_game()
	if err != OK:
		_status.text = "Could not host on port %d (is another game already hosting on this PC?)" % Net.PORT
		return
	show_lobby()


func _on_join(ip: String) -> void:
	if not _check_name():
		return
	ip = ip.strip_edges()
	if not ip.is_valid_ip_address():
		_status.text = "That doesn't look like an IP address."
		return
	if Net.join_game(ip) != OK:
		_status.text = "Could not start connecting."
		return
	_status.text = "Connecting to %s..." % ip


func _check_name() -> bool:
	Net.player_name = _name_edit.text.strip_edges()
	if Net.player_name.is_empty():
		_status.text = "Pick a name first."
		return false
	Net.save_settings()
	return true


# --- Lobby -------------------------------------------------------------------

func _build_lobby_page() -> Control:
	var page := _centered_panel(1080)
	var box: VBoxContainer = page.get_meta("box")
	var title := UiTheme.outlined("Lobby", 44, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_address_label = UiTheme.label("", 18, UiTheme.MUTED)
	_address_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_address_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_address_label)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	box.add_child(columns)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)
	_players_title = UiTheme.label("Players", 20, UiTheme.TEXT)
	left.add_child(_players_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_players_box = VBoxContainer.new()
	_players_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_players_box)
	_bot_buttons = HBoxContainer.new()
	_bot_buttons.add_theme_constant_override("separation", 8)
	left.add_child(_bot_buttons)
	var add_bot := Button.new()
	add_bot.text = "Add bot"
	add_bot.pressed.connect(Net.add_bot)
	_bot_buttons.add_child(add_bot)
	var remove_bot := Button.new()
	remove_bot.text = "Remove bot"
	remove_bot.pressed.connect(Net.remove_bot)
	_bot_buttons.add_child(remove_bot)

	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(middle)
	middle.add_child(UiTheme.label("Your setup", 20, UiTheme.TEXT))
	_loadout = LoadoutPanel.new()
	middle.add_child(_loadout)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 6)
	columns.add_child(right)
	right.add_child(UiTheme.label("How to play", 20, UiTheme.TEXT))
	var rules := UiTheme.label(
		"Hiders mimic props and survive until the timer runs out; health regrows after a few quiet seconds. "
		+ "Seekers shoot bolts at anything suspicious. Found hiders join the seekers.\n\n"
		+ "HIDER  E mimic · R lock rotation · T taunt (+points)\n"
		+ "SEEKER  Left click shoot bolts\n"
		+ "BOTH  Q / F your two spells\n"
		+ "WASD move · Space jump · Shift run · Tab scores · Esc menu",
		16, UiTheme.MUTED)
	rules.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rules.custom_minimum_size = Vector2(300, 0)
	right.add_child(rules)

	_host_settings = VBoxContainer.new()
	right.add_child(_host_settings)
	_hide_spin = _spin_row(_host_settings, "Hiding time (s)", 15, 120, 5, Game.hide_time)
	_seek_spin = _spin_row(_host_settings, "Seeking time (s)", 60, 600, 30, Game.seek_time)

	_waiting_label = UiTheme.label("Waiting for the host to start...", 18, UiTheme.ACCENT)
	box.add_child(_waiting_label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var leave := Button.new()
	leave.text = "Leave"
	leave.pressed.connect(func(): Net.leave())
	buttons.add_child(leave)
	_start_button = Button.new()
	_start_button.text = "Start game"
	_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_button.pressed.connect(func(): Game.host_start_game(_hide_spin.value, _seek_spin.value))
	buttons.add_child(_start_button)
	return page


func _spin_row(parent: Control, text: String, lo: float, hi: float, step: float, value: float) -> SpinBox:
	var row := HBoxContainer.new()
	var l := UiTheme.label(text, 17, UiTheme.MUTED)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.step = step
	spin.value = value
	row.add_child(spin)
	parent.add_child(row)
	return spin


func _refresh_lobby() -> void:
	if _players_box == null or not _lobby_page.visible:
		return
	for c in _players_box.get_children():
		c.queue_free()
	var ids: Array = Net.players.keys()
	ids.sort()
	for id in ids:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var swatch := ColorRect.new()
		swatch.color = Net.get_player_color(id)
		swatch.custom_minimum_size = Vector2(18, 18)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(swatch)
		var text := Net.get_player_name(id)
		if id == 1:
			text += "  (host)"
		if id == multiplayer.get_unique_id():
			text += "  (you)"
		var team: String = Net.players[id].get("team", "auto")
		if team != "auto":
			text += "  - wants %s" % ("hiders" if team == "hider" else "seekers")
		row.add_child(UiTheme.label(text, 19, UiTheme.MUTED if Net.is_bot(id) else UiTheme.TEXT))
		_players_box.add_child(row)
	_players_title.text = "Players (%d/%d)" % [ids.size(), Net.MAX_PLAYERS]
	var host := Net.is_host()
	_bot_buttons.visible = host
	_loadout.refresh()
	_host_settings.visible = host
	_start_button.visible = host
	_waiting_label.visible = not host
	if host:
		var addresses := Net.local_addresses()
		_address_label.text = "Friends can join at: %s  (or pick your game from their LAN list)" % ", ".join(addresses) if not addresses.is_empty() else "Friends can join with your PC's LAN IP address."
		_start_button.text = "Start game" if ids.size() > 1 else "Start practice (solo)"
	else:
		_address_label.text = "Connected to %s's game" % Net.get_player_name(1)


# --- Helpers -----------------------------------------------------------------

func _centered_panel(width: float) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(width, 0)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	center.set_meta("box", box)
	return center


func _spacer(height: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	return c


## Soft coloured circles behind the menu, echoing the hider blobs.
func _add_backdrop_blobs() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 14:
		var blob := Panel.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Net.COLORS[i % Net.COLORS.size()]
		style.bg_color.a = 0.18
		var r := rng.randf_range(60, 180)
		style.set_corner_radius_all(int(r))
		blob.add_theme_stylebox_override("panel", style)
		blob.size = Vector2(r * 2, r * 2)
		blob.set_anchors_preset(Control.PRESET_TOP_LEFT)
		blob.position = Vector2(rng.randf_range(-100, 1700), rng.randf_range(-100, 1000))
		blob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(blob)
