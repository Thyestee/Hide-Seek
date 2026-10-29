extends VBoxContainer
## Team choice and the two spells per team. Used in the lobby and the Esc menu;
## every change is saved and sent to the host straight away.

const UiTheme = preload("res://scripts/ui/ui_theme.gd")
const Spells = preload("res://scripts/spells.gd")

const TEAM_LABELS := {"auto": "Auto (host decides)", "hider": "Hiders", "seeker": "Seekers"}

var _team: OptionButton
var _pickers := {}  # team -> [OptionButton, OptionButton]
var _desc: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UiTheme.label("Team", 17, UiTheme.MUTED))
	_team = OptionButton.new()
	for team in Net.TEAMS:
		_team.add_item(TEAM_LABELS[team])
	_team.item_selected.connect(func(_i): _apply())
	add_child(_team)
	var hint := UiTheme.label("Picking Seekers mid-round switches you now; Hiders applies next round.", 14, UiTheme.MUTED.darkened(0.15))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(hint)
	for team in ["hider", "seeker"]:
		add_child(UiTheme.label("Hider spells" if team == "hider" else "Seeker spells", 17, UiTheme.MUTED))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		add_child(row)
		var pair := []
		for slot in 2:
			var picker := OptionButton.new()
			picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			for spell in Spells.for_team(team):
				picker.add_item(Spells.spell_name(spell))
				picker.set_item_metadata(picker.item_count - 1, spell)
			picker.item_selected.connect(func(_i): _on_spell_picked(team, slot))
			picker.mouse_entered.connect(func(): _describe(picker))
			row.add_child(picker)
			pair.append(picker)
		_pickers[team] = pair
	_desc = UiTheme.label("", 14, UiTheme.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_desc.custom_minimum_size = Vector2(0, 40)
	add_child(_desc)
	refresh()


## Shows the saved choices.
func refresh() -> void:
	_team.select(Net.TEAMS.find(Net.team_preference))
	for team in _pickers:
		for slot in 2:
			var picker: OptionButton = _pickers[team][slot]
			var wanted: String = Net.loadout[team][slot]
			for i in picker.item_count:
				if picker.get_item_metadata(i) == wanted:
					picker.select(i)


func _on_spell_picked(team: String, slot: int) -> void:
	var pair: Array = _pickers[team]
	var mine: OptionButton = pair[slot]
	var other: OptionButton = pair[1 - slot]
	# The same spell can't sit in both slots: swap them instead.
	if mine.get_selected_metadata() == other.get_selected_metadata():
		var previous: String = Net.loadout[team][slot]
		for i in other.item_count:
			if other.get_item_metadata(i) == previous:
				other.select(i)
	_describe(mine)
	_apply()


func _describe(picker: OptionButton) -> void:
	var spell: String = picker.get_selected_metadata()
	_desc.text = "%s: %s (%ds cooldown)" % [Spells.spell_name(spell), Spells.SPELLS[spell].desc, int(Spells.cooldown(spell))]


func _apply() -> void:
	var picks := {}
	for team in _pickers:
		picks[team] = [_pickers[team][0].get_selected_metadata(), _pickers[team][1].get_selected_metadata()]
	Net.set_preferences(Net.TEAMS[_team.selected], picks)
