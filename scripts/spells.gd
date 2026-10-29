extends RefCounted
## Spell catalogue. Every player equips two spells per team, cast with the
## two spell keys. Cooldowns are per spell, so swapping doesn't reset them.

const SPELLS := {
	# Hiders
	"decoy": {"name": "Decoy", "team": "hider", "cooldown": 18.0,
		"desc": "Drop a copy of your current prop where you stand."},
	"blink": {"name": "Blink", "team": "hider", "cooldown": 10.0,
		"desc": "Dash a few metres in the direction you're moving."},
	"smoke": {"name": "Smoke Cloud", "team": "hider", "cooldown": 28.0,
		"desc": "Fill the area around you with thick smoke for 7 seconds."},
	"echo": {"name": "Echo", "team": "hider", "cooldown": 14.0,
		"desc": "Throw your voice: a taunt plays wherever you're aiming."},
	"clutter": {"name": "Clutter", "team": "hider", "cooldown": 35.0,
		"desc": "Sprout five random small props around you."},
	"regrow": {"name": "Regrow", "team": "hider", "cooldown": 30.0,
		"desc": "Instantly heal 40 HP."},
	# Seekers
	"sonar": {"name": "Sonar", "team": "seeker", "cooldown": 20.0,
		"desc": "Every hider within 14 m lets out a ping."},
	"flare": {"name": "Reveal Flare", "team": "seeker", "cooldown": 26.0,
		"desc": "Throw a flare. Hiders near where it lands are marked for 4 seconds."},
	"snare": {"name": "Snare", "team": "seeker", "cooldown": 22.0,
		"desc": "Set a trap only seekers can see. It roots and marks the first hider to touch it."},
	"scatter": {"name": "Scatter Shot", "team": "seeker", "cooldown": 12.0,
		"desc": "Fire a spread of five bolts at once."},
	"haste": {"name": "Haste", "team": "seeker", "cooldown": 16.0,
		"desc": "Run 60% faster for 4 seconds."},
	"shockwave": {"name": "Shockwave", "team": "seeker", "cooldown": 24.0,
		"desc": "A pulse that hits every hider within 4 m for 15 damage."},
}

const DEFAULT_LOADOUT := {"hider": ["decoy", "blink"], "seeker": ["sonar", "scatter"]}


static func for_team(team: String) -> Array:
	var out := []
	for id in SPELLS:
		if SPELLS[id].team == team:
			out.append(id)
	return out


static func spell_name(id: String) -> String:
	return SPELLS[id].name if SPELLS.has(id) else id


static func cooldown(id: String) -> float:
	return SPELLS[id].cooldown if SPELLS.has(id) else 0.0


## Repairs a loadout received from the network or a settings file.
static func sanitize(loadout) -> Dictionary:
	var out := {}
	for team in ["hider", "seeker"]:
		var picks: Array = []
		if loadout is Dictionary and loadout.get(team) is Array:
			for id in loadout[team]:
				if SPELLS.has(id) and SPELLS[id].team == team and not id in picks:
					picks.append(id)
		for id in DEFAULT_LOADOUT[team] + for_team(team):
			if picks.size() >= 2:
				break
			if not id in picks:
				picks.append(id)
		out[team] = picks.slice(0, 2)
	return out


static func random_loadout() -> Dictionary:
	var out := {}
	for team in ["hider", "seeker"]:
		var pool := for_team(team)
		pool.shuffle()
		out[team] = pool.slice(0, 2)
	return out
