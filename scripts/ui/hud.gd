extends CanvasLayer
## In-game overlay: timer, role, abilities, messages, scoreboard and pause menu.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const PropLib = preload("res://scripts/world/prop_library.gd")

var ui_theme: Theme

var _root: Control
var _timer_label: Label
var _count_label: Label
var _role_label: Label
var _hint_label: Label
var _prompt_label: Label
var _hp_bar: ProgressBar
var _crosshair: Label
var _feed: VBoxContainer
var _blackout: ColorRect
var _blackout_label: Label
var _scoreboard: PanelContainer
var _score_grid: GridContainer
var _end_panel: PanelContainer
var _end_title: Label
var _end_sub: Label
var _pause_panel: Control
var _lobby_button: Button
var _damage: ColorRect
var _last_tick := -1


func _ready() -> void:
	_root = Control.new()
	_root.theme = ui_theme
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_build()
	Game.message.connect(_on_message)
	Game.local_hit.connect(_on_local_hit)
	Game.hit_confirmed.connect(_on_hit_confirmed)
	Game.scores_changed.connect(_refresh_scoreboard)
	Game.roles_changed.connect(_refresh_scoreboard)
	Game.round_ended.connect(_on_round_ended)
	Game.phase_changed.connect(func(_p): _end_panel.visible = Game.phase == Game.Phase.ROUND_END)


func _build() -> void:
	_damage = ColorRect.new()
	_damage.color = Color(1, 0.1, 0.1, 0)
	_damage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_damage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_damage)

	_blackout = ColorRect.new()
	_blackout.color = Color(0.03, 0.03, 0.06, 0.97)
	_blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_blackout)
	_blackout_label = UiTheme.outlined("", 34)
	_blackout_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_blackout_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_blackout_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_blackout.add_child(_blackout_label)

	# Top centre: timer and head count.
	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.offset_top = 12
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	_timer_label = UiTheme.outlined("", 38)
	_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_timer_label)
	_count_label = UiTheme.outlined("", 20, UiTheme.MUTED)
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	top.add_child(_count_label)

	# Top left: role.
	_role_label = UiTheme.outlined("", 30)
	_role_label.position = Vector2(24, 16)
	_root.add_child(_role_label)

	# Top right: message feed.
	_feed = VBoxContainer.new()
	_feed.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_feed.offset_left = -560
	_feed.offset_right = -20
	_feed.offset_top = 16
	_feed.alignment = BoxContainer.ALIGNMENT_BEGIN
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)

	# Centre: crosshair and the "press E" prompt.
	_crosshair = UiTheme.outlined("+", 30)
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_crosshair.offset_left = -20
	_crosshair.offset_right = 20
	_crosshair.offset_top = -22
	_crosshair.offset_bottom = 18
	_crosshair.pivot_offset = Vector2(20, 20)
	_root.add_child(_crosshair)
	_prompt_label = UiTheme.outlined("", 22, UiTheme.ACCENT)
	_prompt_label.set_anchors_preset(Control.PRESET_CENTER)
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.offset_left = -300
	_prompt_label.offset_right = 300
	_prompt_label.offset_top = 30
	_prompt_label.offset_bottom = 60
	_root.add_child(_prompt_label)

	# Bottom: health and ability hints.
	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bottom.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bottom.offset_bottom = -18
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bottom)
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = Game.MAX_HP
	_hp_bar.custom_minimum_size = Vector2(320, 22)
	_hp_bar.show_percentage = false
	_hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	bottom.add_child(_hp_bar)
	_hint_label = UiTheme.outlined("", 20)
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bottom.add_child(_hint_label)

	_build_scoreboard()
	_build_end_panel()
	_build_pause_menu()


func _build_scoreboard() -> void:
	_scoreboard = PanelContainer.new()
	_scoreboard.set_anchors_preset(Control.PRESET_CENTER)
	_scoreboard.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_scoreboard.grow_vertical = Control.GROW_DIRECTION_BOTH
	_scoreboard.custom_minimum_size = Vector2(560, 0)
	_scoreboard.visible = false
	_root.add_child(_scoreboard)
	var box := VBoxContainer.new()
	_scoreboard.add_child(box)
	var title := UiTheme.outlined("Scores", 30, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	_score_grid = GridContainer.new()
	_score_grid.columns = 3
	_score_grid.add_theme_constant_override("h_separation", 30)
	box.add_child(_score_grid)


func _build_end_panel() -> void:
	_end_panel = PanelContainer.new()
	_end_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_end_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_panel.offset_top = 110
	_end_panel.custom_minimum_size = Vector2(520, 0)
	_end_panel.visible = false
	_root.add_child(_end_panel)
	var box := VBoxContainer.new()
	_end_panel.add_child(box)
	_end_title = UiTheme.outlined("", 46, UiTheme.ACCENT)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_title)
	_end_sub = UiTheme.label("", 20, UiTheme.MUTED)
	_end_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_end_sub)


func _build_pause_menu() -> void:
	_pause_panel = CenterContainer.new()
	_pause_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_pause_panel.visible = false
	_root.add_child(_pause_panel)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(420, 0)
	_pause_panel.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := UiTheme.outlined("Menu", 36, UiTheme.ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var resume := Button.new()
	resume.text = "Resume"
	resume.pressed.connect(_close_pause)
	box.add_child(resume)
	box.add_child(UiTheme.label("Mouse sensitivity", 16, UiTheme.MUTED))
	var slider := HSlider.new()
	slider.min_value = 0.2
	slider.max_value = 3.0
	slider.step = 0.05
	slider.value = Net.mouse_sensitivity
	slider.value_changed.connect(func(v):
		Net.mouse_sensitivity = v
		Net.save_settings()
	)
	box.add_child(slider)
	_lobby_button = Button.new()
	_lobby_button.text = "End game, back to lobby"
	_lobby_button.pressed.connect(func(): Game.host_return_to_lobby())
	box.add_child(_lobby_button)
	var leave := Button.new()
	leave.text = "Leave game"
	leave.pressed.connect(func(): Net.leave())
	box.add_child(leave)
	var quit := Button.new()
	quit.text = "Quit to desktop"
	quit.pressed.connect(func(): get_tree().quit())
	box.add_child(quit)


# --- Per-frame update --------------------------------------------------------

func _process(_delta: float) -> void:
	if not visible or not Game.in_game():
		return
	var me := Game.local_player()
	var role := Game.my_role()
	var seconds := ceili(Game.time_left)
	var clock := "%d:%02d" % [seconds / 60, seconds % 60]
	if Game.phase == Game.Phase.HIDING:
		_timer_label.text = "HIDE!  %s" % clock
		if seconds <= 5 and seconds != _last_tick and seconds > 0:
			Sfx.play("tick")
	elif Game.phase == Game.Phase.SEEKING:
		_timer_label.text = "SEEK  %s" % clock
		if seconds <= 10 and seconds != _last_tick and seconds > 0:
			Sfx.play("tick", -6.0)
	elif Game.phase == Game.Phase.ROUND_END:
		_timer_label.text = "Round over"
		_end_sub.text = "Next round in %d..." % seconds
	_last_tick = seconds
	_count_label.text = "Hiders left: %d    Seekers: %d" % [Game.count_role("hider"), Game.count_role("seeker")]

	if role == "seeker":
		_role_label.text = "SEEKER"
		_role_label.add_theme_color_override("font_color", Color(1.0, 0.5, 0.45))
	else:
		_role_label.text = "HIDER"
		_role_label.add_theme_color_override("font_color", Color(0.5, 1.0, 0.55))

	var frozen: bool = me != null and me.frozen
	_blackout.visible = frozen
	if frozen:
		_blackout_label.text = "You are a SEEKER\n\nThe hiders are hiding...\nYou are released in %s" % clock

	_hp_bar.visible = role == "hider"
	_hp_bar.value = Game.hp.get(Game.my_id(), Game.MAX_HP)
	_hint_label.text = _hints(me, role)
	_prompt_label.text = ""
	if me and role == "hider" and me.look_prop != "" and me.look_prop != me.disguise:
		_prompt_label.text = "[%s] Become: %s" % [Game.key_label("mimic"), PropLib.display_name(me.look_prop)]
	_lobby_button.visible = Net.is_host()

	var show_scores := Input.is_action_pressed("scoreboard") and not _pause_panel.visible
	if show_scores and not _scoreboard.visible:
		_refresh_scoreboard()
	_scoreboard.visible = show_scores


func _hints(me: Node, role: String) -> String:
	if me == null:
		return ""
	if role == "seeker":
		var sonar := "ready" if me.sonar_cooldown <= 0.0 else "%ds" % ceili(me.sonar_cooldown)
		return "[%s] Bonk     [%s / RMB] Sonar: %s     [Shift] Run" % [Game.key_label("swing"), Game.key_label("sonar"), sonar]
	var lock := "on" if me.rotation_locked else "off"
	var taunt := "ready" if me.taunt_cooldown <= 0.0 else "%ds" % ceili(me.taunt_cooldown)
	return "[%s] Mimic     [%s] Lock rotation: %s     [%s] Taunt: %s     [%s] Decoy x%d" % [
		Game.key_label("mimic"), Game.key_label("lock_rotation"), lock,
		Game.key_label("taunt"), taunt, Game.key_label("decoy"), Game.decoys_left,
	]


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not Game.in_game():
		return
	if event.is_action_pressed("pause"):
		if _pause_panel.visible:
			_close_pause()
		else:
			_pause_panel.visible = true
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not _pause_panel.visible:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			# Clicking back into the window (after alt-tab) recaptures the mouse.
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()


func _close_pause() -> void:
	_pause_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func on_game_started() -> void:
	_pause_panel.visible = false
	_end_panel.visible = false
	for c in _feed.get_children():
		c.queue_free()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# --- Events ------------------------------------------------------------------

func _on_message(text: String, color: Color) -> void:
	var l := UiTheme.outlined(text, 20, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feed.add_child(l)
	while _feed.get_child_count() > 6:
		var oldest := _feed.get_child(0)
		_feed.remove_child(oldest)
		oldest.queue_free()
	var tween := l.create_tween()
	tween.tween_interval(5.0)
	tween.tween_property(l, "modulate:a", 0.0, 0.8)
	tween.tween_callback(l.queue_free)


func _on_local_hit(_hp: int) -> void:
	_damage.color.a = 0.45
	var tween := create_tween()
	tween.tween_property(_damage, "color:a", 0.0, 0.5)


func _on_hit_confirmed() -> void:
	_crosshair.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	_crosshair.scale = Vector2(1.8, 1.8)
	var tween := create_tween()
	tween.tween_property(_crosshair, "scale", Vector2.ONE, 0.25)
	tween.tween_callback(func(): _crosshair.add_theme_color_override("font_color", UiTheme.TEXT))


func _on_round_ended(winner: String) -> void:
	_end_title.text = "HIDERS WIN!" if winner == "hiders" else "SEEKERS WIN!"
	_end_panel.visible = true


func _refresh_scoreboard() -> void:
	if _score_grid == null:
		return
	for c in _score_grid.get_children():
		_score_grid.remove_child(c)
		c.queue_free()
	for header in ["Player", "Role", "Score"]:
		_score_grid.add_child(UiTheme.label(header, 16, UiTheme.MUTED))
	var ids: Array = Net.players.keys()
	ids.sort_custom(func(a, b): return Game.scores.get(a, 0) > Game.scores.get(b, 0))
	for id in ids:
		var you := "  (you)" if id == Game.my_id() else ""
		_score_grid.add_child(UiTheme.label(Net.get_player_name(id) + you, 19, Net.get_player_color(id).lightened(0.3)))
		var role: String = Game.roles.get(id, "-")
		_score_grid.add_child(UiTheme.label(role.capitalize(), 19))
		_score_grid.add_child(UiTheme.label(str(Game.scores.get(id, 0)), 19))
