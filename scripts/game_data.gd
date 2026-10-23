extends Node
## GameData (AUTOLOAD) – all tuning numbers from the GDD in one place,
## plus input-map registration so the project needs no manual Input Map setup.

const MAX_PLAYERS := 3
const WAVES := 5
const SUBWAVES := 3
const YARD_DURATION := 60.0
const KITCHEN_PREP := 10.0
const YARD_REVIVE_TIME := 10.0
const TABLE_MAX_FOOD := 600.0
const TABLE_AURA_RADIUS := 96.0   # 3 tiles * 32px
const TABLE_AURA_REGEN := 0.03    # 3% max HP per second
const SPEED_SCALE := 0.6          # GDD SPD (e.g. 310) -> px/s
const BASE_CRIT_RATE := 0.05
const BASE_CRIT_DMG := 1.5

enum Difficulty { NORMAL, HARD, HELL }

const DIFFICULTY := {
	Difficulty.NORMAL: {"name": "Normal", "vectors": 1, "hp": 1.00, "atk": 1.00, "telegraph": 1.2, "reward": 1.0, "elites": false},
	Difficulty.HARD:   {"name": "Hard",   "vectors": 2, "hp": 1.65, "atk": 1.30, "telegraph": 0.9, "reward": 1.5, "elites": false},
	Difficulty.HELL:   {"name": "Hell",   "vectors": 3, "hp": 2.50, "atk": 1.75, "telegraph": 0.7, "reward": 2.2, "elites": true},
}

# Back-loaded payouts per defended wave (index = wave - 1).
const WAVE_PURPLE := [1, 2, 4, 7, 11]
const WAVE_CAPS := [1, 2, 4, 7, 11]
const WAVE_GREEN := [200, 300, 450, 700, 1350]
# PLACEHOLDER – GDD says "equal burst of Bonus Ether" but gives no numbers.
const FEAST_BONUS_ETHER := [50, 75, 100, 140, 180]

# Enemy mix per wave (repeats = higher spawn weight).
const WAVE_POOLS := {
	1: ["forager_ant", "forager_ant", "forager_ant", "sprinter_roach"],
	2: ["forager_ant", "forager_ant", "sprinter_roach", "fencer_fly", "maggot_mortar"],
	3: ["forager_ant", "sprinter_roach", "fencer_fly", "maggot_mortar", "shield_ant"],
	4: ["forager_ant", "sprinter_roach", "fencer_fly", "maggot_mortar", "shield_ant", "gutter_rat"],
	5: ["forager_ant", "sprinter_roach", "fencer_fly", "maggot_mortar", "shield_ant", "gutter_rat"],
}

# ---------------------------------------------------------------------------
# ENEMIES  – hp = [wave-1 value, last-wave value]; "attacks" drive enemy.gd
# ---------------------------------------------------------------------------
const ENEMIES := {
	"forager_ant": {"name": "Forager Ant", "hp": [90, 280], "atk": 12, "ether": 4, "speed": 70.0, "radius": 10.0,
		"color": Color("8b3a2b"),
		"attacks": [{"kind": "bite", "range": 22.0, "mult": 1.0, "cd": 1.0}]},
	"sprinter_roach": {"name": "Sprinter Roach", "hp": [140, 420], "atk": 18, "ether": 7, "speed": 95.0, "radius": 12.0,
		"color": Color("6b4423"),
		"attacks": [{"kind": "dash", "range": 260.0, "mult": 2.0, "cd": 3.5, "dist": 280.0}]},
	"fencer_fly": {"name": "Fencer Fly", "hp": [110, 350], "atk": 22, "ether": 8, "speed": 85.0, "radius": 11.0,
		"color": Color("3a5f8b"),
		"attacks": [{"kind": "dive", "range": 280.0, "mult": 0.8, "cd": 3.2, "hits": 3, "radius": 55.0}]},
	"shield_ant": {"name": "Shield Ant", "hp": [260, 800], "atk": 15, "ether": 10, "speed": 60.0, "radius": 14.0,
		"color": Color("a0522d"), "block": 0.5,
		"attacks": [{"kind": "bash", "range": 70.0, "mult": 1.0, "cd": 3.0, "arc": 90.0, "stun": 1.0}]},
	"gutter_rat": {"name": "Gutter Rat", "hp": [400, 1250], "atk": 30, "ether": 15, "speed": 55.0, "radius": 18.0,
		"color": Color("5a5a66"),
		"attacks": [{"kind": "slam", "range": 90.0, "mult": 2.5, "cd": 4.0, "radius": 85.0}]},
	"maggot_mortar": {"name": "Maggot Mortar", "hp": [160, 480], "atk": 25, "ether": 12, "speed": 45.0, "radius": 12.0,
		"color": Color("b5c76a"), "keep": 240.0,
		"attacks": [{"kind": "lob", "range": 330.0, "mult": 0.0, "cd": 4.0, "puddle_radius": 40.0, "puddle_dps": 15.0}]},
	# Minibosses: hp ramps across their own wave span.
	"sir_roachalot": {"name": "Sir Roachalot", "hp": [3500, 5500], "waves": [1, 2], "atk": 45, "ether": 60, "speed": 50.0,
		"radius": 26.0, "color": Color("c0392b"), "miniboss": true, "boss": true,
		"attacks": [{"kind": "drift", "range": 2000.0, "mult": 1.2, "cd": 5.0, "lanes": 3}]},
	"ratatouille": {"name": "Ratatouille the Butcher", "hp": [8500, 12000], "waves": [3, 4], "atk": 65, "ether": 90, "speed": 60.0,
		"radius": 28.0, "color": Color("7d3c98"), "miniboss": true, "boss": true,
		"attacks": [{"kind": "forks", "range": 420.0, "mult": 1.0, "cd": 4.0, "length": 420.0},
					{"kind": "cleave", "range": 120.0, "mult": 1.5, "cd": 3.0, "radius": 115.0}]},
	"trash_king": {"name": "The Trash King", "hp": [28000], "atk": 90, "ether": 0, "speed": 35.0,
		"radius": 40.0, "color": Color("27ae60"), "boss": true,
		"attacks": [{"kind": "summon", "range": 3000.0, "mult": 0.0, "cd": 12.0},
					{"kind": "garbage", "range": 3000.0, "mult": 1.0, "cd": 5.0}],
		"attacks_p2": [{"kind": "shock", "range": 3000.0, "mult": 1.2, "cd": 4.0}],
		"eat_dps": 25.0},
}

# ---------------------------------------------------------------------------
# CHARACTERS – base stats + basic attack shape + 2 skills (data-driven; see skills.gd)
# skill damage = (base * level_mult + coef * ATK) * (1 + item skill power)   [ASSUMPTION]
# ---------------------------------------------------------------------------
const CHARACTERS := {
	"nanay_tala": {"name": "Nanay Tala", "role": "Slipper Striker", "color": Color("e8a33d"),
		"hp": 650, "atk": 38, "aspd": 1.20, "spd": 310,
		"attack": {"type": "melee", "range": 75.0, "arc": 110.0},
		"skill1": {"name": "Housewife Hustle", "cd": 9.0, "kind": "buff_self", "dur": 4.0, "mods": {"spd": 0.35, "aspd": 0.25}},
		"skill2": {"name": "Planet-Cracker Smack", "cd": 26.0, "kind": "aoe", "radius": 130.0, "base": 220.0, "coef": 1.8, "stun": 2.2}},
	"pip": {"name": "Pip", "role": "Pepper Gunner", "color": Color("e74c3c"),
		"hp": 480, "atk": 28, "aspd": 1.65, "spd": 305,
		"attack": {"type": "ranged", "range": 340.0, "width": 14.0},
		"skill1": {"name": "Sneeze Cloud", "cd": 10.0, "kind": "dash_zone", "dash": -140.0, "zone_offset": 0.0,
			"radius": 90.0, "dps": 0.0, "slow": 0.4, "dur": 3.0},
		"skill2": {"name": "Seasoning Barrage", "cd": 28.0, "kind": "volley", "waves": 8, "dur": 3.5, "radius": 230.0,
			"base": 45.0, "coef": 0.0, "shred": 0.2}},
	"broomsworth": {"name": "Broomsworth", "role": "The Sweeper", "color": Color("8e6e53"),
		"hp": 750, "atk": 32, "aspd": 1.05, "spd": 295,
		"attack": {"type": "melee", "range": 85.0, "arc": 120.0},
		"skill1": {"name": "Dustpan Scoop", "cd": 8.0, "kind": "cone", "range": 130.0, "arc": 100.0, "base": 90.0, "coef": 0.0, "push": 90.0},
		"skill2": {"name": "Whirlwind Cleanse", "cd": 30.0, "kind": "vortex", "dur": 4.5, "radius": 150.0, "dps": 65.0}},
	"suds": {"name": "Suds", "role": "Dish Alchemist", "color": Color("5dade2"),
		"hp": 520, "atk": 25, "aspd": 1.30, "spd": 300,
		"attack": {"type": "ranged", "range": 280.0, "width": 18.0},
		"skill1": {"name": "Slippery Floor", "cd": 11.0, "kind": "zone", "range": 260.0, "radius": 110.0, "dps": 0.0,
			"slow": 0.25, "ally_spd": 0.25, "dur": 5.0},
		"skill2": {"name": "Mega Bubble Dome", "cd": 34.0, "kind": "dome", "dur": 3.5, "radius": 140.0, "pop": 200.0}},
	"skewer": {"name": "Skewer", "role": "Toothpick Ronin", "color": Color("f4d03f"),
		"hp": 540, "atk": 44, "aspd": 1.45, "spd": 325,
		"attack": {"type": "melee", "range": 65.0, "arc": 80.0},
		"skill1": {"name": "Shadow Step", "cd": 8.0, "kind": "tp_crit", "range": 320.0, "crits": 2},
		"skill2": {"name": "Thousand Hors d'Oeuvres", "cd": 25.0, "kind": "flurry", "dur": 1.5, "hits": 6, "radius": 110.0, "atk_coef": 0.6}},
	"clank": {"name": "Clank", "role": "Colander Knight", "color": Color("95a5a6"),
		"hp": 850, "atk": 30, "aspd": 0.95, "spd": 285,
		"attack": {"type": "melee", "range": 80.0, "arc": 110.0},
		"skill1": {"name": "Pot-Bang Taunt", "cd": 12.0, "kind": "taunt_shield", "shield": 200.0, "dur": 3.5, "radius": 220.0},
		"skill2": {"name": "Boiling Spill", "cd": 32.0, "kind": "zone", "range": 160.0, "radius": 150.0, "burst": 180.0, "dps": 35.0, "dur": 5.0}},
	"flick": {"name": "Flick", "role": "Matchstick Pyro", "color": Color("e67e22"),
		"hp": 490, "atk": 26, "aspd": 1.25, "spd": 300,
		"attack": {"type": "ranged", "range": 300.0, "width": 16.0},
		"skill1": {"name": "Spark Hop", "cd": 9.0, "kind": "dash_zone", "dash": 140.0, "zone_offset": 0.5,
			"radius": 60.0, "dps": 40.0, "dur": 3.0},
		"skill2": {"name": "Grease Fire", "cd": 28.0, "kind": "zone", "range": 280.0, "radius": 150.0, "burst": 240.0, "dps": 50.0, "dur": 5.0}},
	"snap": {"name": "Snap", "role": "Rubber-Band Sniper", "color": Color("1abc9c"),
		"hp": 460, "atk": 48, "aspd": 0.90, "spd": 300,
		"attack": {"type": "ranged", "range": 480.0, "width": 12.0},
		"skill1": {"name": "Spring Wire", "cd": 10.0, "kind": "line", "length": 300.0, "width": 24.0, "base": 110.0, "coef": 0.0, "push": 120.0},
		"skill2": {"name": "Giant Elastic Ballista", "cd": 26.0, "kind": "line", "length": 700.0, "width": 28.0, "base": 350.0, "coef": 0.0, "pin": 2.0}},
	"whisker": {"name": "Whisker", "role": "Pastry Bard", "color": Color("f5b7b1"),
		"hp": 580, "atk": 24, "aspd": 1.35, "spd": 310,
		"attack": {"type": "ranged", "range": 260.0, "width": 16.0},
		"skill1": {"name": "Sugar Rush", "cd": 9.0, "kind": "heal_ally", "base": 140.0, "coef": 1.2, "dur": 3.0, "mods": {"aspd": 0.25}},
		"skill2": {"name": "Grand Banquet Buff", "cd": 35.0, "kind": "team_buff", "dur": 5.0, "mods": {"atk": 0.30, "spd": 0.20, "lifesteal": 0.15}}},
	"goo": {"name": "Goo", "role": "Glue Trapper", "color": Color("af7ac5"),
		"hp": 560, "atk": 27, "aspd": 1.20, "spd": 295,
		"attack": {"type": "ranged", "range": 280.0, "width": 18.0},
		"skill1": {"name": "Sticky Patch", "cd": 10.0, "kind": "zone", "range": 260.0, "radius": 70.0, "dps": 0.0,
			"root": 2.5, "max_targets": 5, "dur": 6.0},
		"skill2": {"name": "Mecha-Mousetrap", "cd": 30.0, "kind": "trap", "range": 400.0, "radius": 130.0, "snaps": 4,
			"interval": 0.7, "base": 220.0, "coef": 0.0}},
}


func _ready() -> void:
	_register_inputs()


# Level multiplier from GDD: +1% per normal level, +9% on every 10th level.
func level_multiplier(level: int) -> float:
	var gained := level - 1
	var milestones := floori(level / 10.0)
	return 1.0 + 0.01 * (gained - milestones) + 0.09 * milestones


func build_stats(char_id: String, level: int) -> Dictionary:
	var c: Dictionary = CHARACTERS[char_id]
	var m := level_multiplier(level)
	return {
		"hp": c.hp * m, "atk": c.atk * m, "aspd": c.aspd, "spd": c.spd,
		"crit_rate": BASE_CRIT_RATE, "crit_dmg": BASE_CRIT_DMG, "skill_mult": m,
	}


func enemy_hp(id: String, wave: int) -> float:
	var e: Dictionary = ENEMIES[id]
	if e.hp.size() == 1:
		return float(e.hp[0])
	var span: Array = e.get("waves", [1, 5])
	var t := clampf(float(wave - span[0]) / maxf(1.0, float(span[1] - span[0])), 0.0, 1.0)
	return lerpf(float(e.hp[0]), float(e.hp[1]), t)


func _register_inputs() -> void:
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("move_up", [KEY_W, KEY_UP])
	_add_key("move_down", [KEY_S, KEY_DOWN])
	_add_key("skill_1", [KEY_Q])
	_add_key("skill_2", [KEY_E])
	_add_key("interact", [KEY_F])
	if not InputMap.has_action("attack"):
		InputMap.add_action("attack")
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("attack", m)


func _add_key(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
