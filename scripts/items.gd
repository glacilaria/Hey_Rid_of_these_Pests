class_name Items
extends RefCounted
## ITEM BUILDING data + pure helper functions (no scene access).
## Tier 1 Common  : bought for 60 Ether.
## Tier 2 Rare    : crafted from Commons + 80 Ether.
## Tier 3 Epic    : crafted from Rare/Common parts + 220 Ether.
##
## "mods" keys:  FLAT  -> atk, hp, crit_rate, crit_dmg   (added to base)
##               PCT   -> aspd, spd, skill_power         (multiplier / additive %)

const MAX_SLOTS := 6
const COST := {1: 60, 2: 80, 3: 220}
const FLAT_KEYS := ["atk", "hp", "crit_rate", "crit_dmg"]

const ITEMS := {
	# ---------------- Tier 1: Common
	"rubber_slipper": {"name": "Rubber Slipper", "tier": 1, "mods": {"atk": 15}, "short": "+15 ATK"},
	"wooden_slingshot": {"name": "Wooden Slingshot", "tier": 1, "mods": {"aspd": 0.15}, "short": "+15% ASPD"},
	"tupperware_lid": {"name": "Tupperware Lid", "tier": 1, "mods": {"hp": 180}, "short": "+180 HP"},
	"fuzzy_socks": {"name": "Fuzzy Socks", "tier": 1, "mods": {"spd": 0.10}, "short": "+10% SPD"},
	"kitchen_battery": {"name": "Kitchen Battery", "tier": 1, "mods": {"skill_power": 0.18}, "short": "+18% Skill"},

	# ---------------- Tier 2: Rare
	"bug_spray": {"name": "Bug Spray", "tier": 2, "parts": ["rubber_slipper", "rubber_slipper", "wooden_slingshot"],
		"mods": {"atk": 35, "aspd": 0.20}, "short": "+35 ATK +20% ASPD",
		"passive": "Basic attacks poison: 10 DMG/s for 3s (stacks x3)."},
	"electric_flyswatter": {"name": "Electric Flyswatter", "tier": 2, "parts": ["rubber_slipper", "wooden_slingshot"],
		"mods": {"atk": 20, "aspd": 0.20, "crit_rate": 0.12}, "short": "+20 ATK +20% ASPD +12% Crit",
		"passive": "Crits shock the target for 25 bonus lightning damage."},
	"snap_trap_gauntlet": {"name": "Snap-Trap Gauntlet", "tier": 2, "parts": ["rubber_slipper", "rubber_slipper"],
		"mods": {"atk": 38, "crit_dmg": 0.35}, "short": "+38 ATK +35% Crit DMG",
		"passive": "Every 5th basic attack is a guaranteed crit."},
	"laser_pointer": {"name": "Laser Pointer", "tier": 2, "parts": ["wooden_slingshot", "kitchen_battery"],
		"mods": {"aspd": 0.20, "skill_power": 0.22, "crit_rate": 0.15}, "short": "+20% ASPD +22% Skill +15% Crit",
		"passive": "Attacks mark enemies: all allies +5% Crit Rate against them."},
	"caffeine_syringe": {"name": "Caffeine Syringe", "tier": 2, "parts": ["wooden_slingshot", "fuzzy_socks"],
		"mods": {"aspd": 0.22, "spd": 0.15, "crit_rate": 0.10}, "short": "+22% ASPD +15% SPD +10% Crit",
		"passive": "Kills grant +15% ASPD for 3s (max 2 stacks)."},
	"cast_iron_pot_lid": {"name": "Cast-Iron Pot Lid", "tier": 2, "parts": ["tupperware_lid", "tupperware_lid"],
		"mods": {"hp": 450}, "short": "+450 HP",
		"passive": "-20% damage from heavy telegraphed attacks."},
	"roller_slippers": {"name": "Roller-Slippers", "tier": 2, "parts": ["rubber_slipper", "fuzzy_socks"],
		"mods": {"atk": 22, "spd": 0.18}, "short": "+22 ATK +18% SPD",
		"passive": "Moving builds static; at 100 your next hit deals +40 DMG."},
	"overclocked_igniter": {"name": "Overclocked Igniter", "tier": 2, "parts": ["rubber_slipper", "kitchen_battery"],
		"mods": {"atk": 22, "skill_power": 0.30, "crit_dmg": 0.25}, "short": "+22 ATK +30% Skill +25% Crit DMG",
		"passive": "Using a skill empowers your next basic attack: +50% ATK damage."},
	"oven_mitt_armor": {"name": "Oven Mitt Armor", "tier": 2, "parts": ["tupperware_lid", "kitchen_battery"],
		"mods": {"hp": 250, "skill_power": 0.28}, "short": "+250 HP +28% Skill",
		"passive": "Taking damage cuts skill cooldowns by 0.5s (1s internal CD)."},

	# ---------------- Tier 3: Epic
	"cockroach_spray": {"name": "Cockroach Spray", "tier": 3, "parts": ["bug_spray", "rubber_slipper"],
		"mods": {"atk": 75, "aspd": 0.45}, "short": "+75 ATK +45% ASPD",
		"passive": "Attacks spray a wide cone: -25% enemy armor, poison stacks x8 (15 DMG/s each)."},
	"high_voltage_zapper": {"name": "High-Voltage Zapper", "tier": 3, "parts": ["electric_flyswatter", "laser_pointer"],
		"mods": {"atk": 45, "aspd": 0.45, "skill_power": 0.25, "crit_rate": 0.28, "crit_dmg": 0.35},
		"short": "+45 ATK +45% ASPD +25% Skill +28% Crit +35% CritDMG",
		"passive": "Crits chain lightning to 4 nearby pests for 60% of the crit damage."},
	"tungsten_slipper": {"name": "Tungsten Slipper", "tier": 3, "parts": ["snap_trap_gauntlet", "overclocked_igniter"],
		"mods": {"atk": 85, "skill_power": 0.40, "crit_dmg": 0.70}, "short": "+85 ATK +40% Skill +70% CritDMG",
		"passive": "Crits deal +8% of target's current HP (cap 150 vs bosses) and micro-stun 0.2s."},
	"sub_zero_fridge_door": {"name": "Sub-Zero Fridge Door", "tier": 3, "parts": ["cast_iron_pot_lid", "oven_mitt_armor"],
		"mods": {"hp": 1000, "skill_power": 0.45}, "short": "+1000 HP +45% Skill",
		"passive": "4m frost aura: pests -30% move speed; you regen 1.5% Max HP/s."},
	"turbo_vacuum_boots": {"name": "Turbo Vacuum Boots", "tier": 3, "parts": ["roller_slippers", "caffeine_syringe"],
		"mods": {"atk": 45, "aspd": 0.45, "spd": 0.30, "crit_rate": 0.18}, "short": "+45 ATK +45% ASPD +30% SPD +18% Crit",
		"passive": "Walk through pests; leave a slipstream giving allies +15% SPD."},
}

const COMMON_IDS := ["rubber_slipper", "wooden_slingshot", "tupperware_lid", "fuzzy_socks", "kitchen_battery"]
const RARE_IDS := ["bug_spray", "electric_flyswatter", "snap_trap_gauntlet", "laser_pointer", "caffeine_syringe",
	"cast_iron_pot_lid", "roller_slippers", "overclocked_igniter", "oven_mitt_armor"]
const EPIC_IDS := ["cockroach_spray", "high_voltage_zapper", "tungsten_slipper", "sub_zero_fridge_door", "turbo_vacuum_boots"]


static func tier(id: String) -> int:
	return ITEMS[id].tier


static func item_name(id: String) -> String:
	return ITEMS[id].name


static func is_common(id: String) -> bool:
	return ITEMS[id].tier == 1


static func cost_of(id: String) -> int:
	return COST[ITEMS[id].tier]


static func count(inv: Array, id: String) -> int:
	var n := 0
	for i in inv:
		if i == id:
			n += 1
	return n


## {part_id: how_many} for a recipe.
static func part_counts(id: String) -> Dictionary:
	var d := {}
	for p in ITEMS[id].get("parts", []):
		d[p] = d.get(p, 0) + 1
	return d


static func can_craft(inv: Array, id: String) -> bool:
	if is_common(id):
		return false
	var parts := part_counts(id)
	for p in parts:
		if count(inv, p) < parts[p]:
			return false
	return true


## Returns the new inventory (parts removed, result added) or null if parts are missing.
static func craft(inv: Array, id: String) -> Variant:
	if not can_craft(inv, id):
		return null
	var out := inv.duplicate()
	for p in ITEMS[id].parts:
		out.erase(p)      # erase() removes one instance
	out.append(id)
	return out


## Sums an inventory into {"flat": {...}, "pct": {...}} for Player.item_flat / item_pct.
static func total_mods(inv: Array) -> Dictionary:
	var flat := {}
	var pct := {}
	for id in inv:
		var mods: Dictionary = ITEMS[id].mods
		for k in mods:
			if k in FLAT_KEYS:
				flat[k] = flat.get(k, 0.0) + mods[k]
			else:
				pct[k] = pct.get(k, 0.0) + mods[k]
	return {"flat": flat, "pct": pct}


static func recipe_text(id: String) -> String:
	var parts: Array[String] = []
	var pc := part_counts(id)
	for p in pc:
		parts.append("%s%s" % [item_name(p), " x%d" % pc[p] if pc[p] > 1 else ""])
	return " + ".join(parts)
