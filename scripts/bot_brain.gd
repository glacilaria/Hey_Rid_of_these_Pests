class_name BotBrain
extends RefCounted
## Teammate AI for the 2 quick-match bots. Runs on the SERVER, driving a normal Player
## node (so bots use exactly the same attack/skill/damage code as humans).
##
## Roles (derived from the character):
##   tank    – Broomsworth, Clank   : walk up to the nearest threat, taunt/sweep, soak damage
##   melee   – Nanay Tala, Skewer   : engage the pest closest to the table
##   ranged  – Pip, Snap, Suds, Flick, Goo : kite at ~75% range, strafe
##   healer  – Whisker              : kite like ranged, heal/buff when allies are hurt
## Yard: hunt the nearest pest (or wander). Kitchen: defend the table, idle on its aura.
## Also dodges red telegraphs and shops at the workbench (see MatchManager._bots_shop).

const BUILDS := {
	"melee": ["tungsten_slipper"],
	"ranged": ["high_voltage_zapper"],
	"tank": ["sub_zero_fridge_door"],
	"support": ["oven_mitt_armor", "overclocked_igniter"],
	"healer": ["oven_mitt_armor", "caffeine_syringe"],
}

var _skill_t := 0.0
var _wander := Vector2.ZERO
var _wander_t := 0.0


static func role(char_id: String) -> String:
	if char_id in ["broomsworth", "clank"]:
		return "tank"
	if char_id == "whisker":
		return "healer"
	if char_id in ["suds", "goo"]:
		return "support"
	if GameData.CHARACTERS[char_id].attack.type == "ranged":
		return "ranged"
	return "melee"


static func build_for(char_id: String) -> Array:
	return BUILDS[role(char_id)]


func think(p: Player, delta: float) -> void:
	var mm := p.get_tree().get_first_node_in_group("match") as MatchManager
	var now := Time.get_ticks_msec() / 1000.0
	if mm == null or p.dead or now < p.stun_until:
		p.velocity = Vector2.ZERO
		return
	var def: Dictionary = GameData.CHARACTERS[p.char_id]
	var reach: float = def.attack.range
	var r := role(p.char_id)
	var in_kitchen := mm.phase != MatchManager.Phase.YARD
	var table_pos := mm.table.global_position

	# ---- choose a target: in the kitchen the pest closest to the table, in the yard closest to me
	var anchor := table_pos if in_kitchen else p.global_position
	var target: Enemy = null
	var best := INF
	var near := 0
	var boss_near := false
	for e in Combat.enemies():
		var dp: float = e.global_position.distance_to(p.global_position)
		if dp < 240.0:
			near += 1
			if e.data.get("boss", false):
				boss_near = true
		var d: float = e.global_position.distance_to(anchor)
		if d < best:
			best = d
			target = e

	# ---- movement intent
	var dir := Vector2.ZERO
	if target:
		var to := target.global_position - p.global_position
		var dist := to.length()
		p.aim = to.normalized()
		match r:
			"melee", "tank":
				if dist > reach * 0.7:
					dir = p.aim
			_:
				if dist < reach * 0.5:
					dir = -p.aim
				elif dist > reach * 0.85:
					dir = p.aim
				else:
					dir = p.aim.orthogonal() * 0.5
		if dist <= reach + 10.0:
			p.srv_attack(p.aim)
	elif in_kitchen:
		var slot := Vector2.from_angle(float(absi(p.peer_id)) * 2.1) * 90.0
		var to_slot := table_pos + slot - p.global_position
		if to_slot.length() > 20.0:
			dir = to_slot.normalized()
	else:
		_wander_t -= delta
		if _wander_t <= 0.0 or p.global_position.distance_to(_wander) < 30.0:
			_wander_t = 3.0
			_wander = Vector2(randf_range(MatchManager.YARD_RECT.position.x + 80.0, MatchManager.YARD_RECT.end.x - 80.0),
				randf_range(MatchManager.YARD_RECT.position.y + 60.0, MatchManager.YARD_RECT.end.y - 60.0))
		dir = (_wander - p.global_position).normalized()

	# ---- dodge red telegraphs (overrides movement)
	var dodge := _dodge(p)
	if dodge != Vector2.ZERO:
		dir = dodge

	p.velocity = dir.normalized() * p.base.spd * GameData.SPEED_SCALE * p.move_mult
	p.move_and_slide()

	# ---- skills (re-evaluated ~3x per second)
	_skill_t -= delta
	if _skill_t <= 0.0:
		_skill_t = 0.3
		_use_skills(p, def, target, near, boss_near, mm, in_kitchen)


func _dodge(p: Player) -> Vector2:
	for e in Combat.enemies():
		if e.state != Enemy.State.TELEGRAPH or e._tele.is_empty():
			continue
		var t: Dictionary = e._tele
		var pos: Vector2 = p.global_position
		match t.shape:
			"circle", "acid":
				var c: Vector2 = t.pos
				if pos.distance_to(c) < t.a + 35.0:
					return (pos - c).normalized()
			"line":
				var d := Vector2.from_angle(t.angle)
				var a: Vector2 = t.pos
				var b := a + d * t.a
				if Combat.seg_dist(pos, a, b) < t.b * 0.5 + 35.0:
					var side := d.orthogonal()
					return side if (pos - a).dot(side) >= 0.0 else -side
			"cone":
				var to := pos - t.pos
				if to.length() < t.a + 30.0 and absf(Vector2.from_angle(t.angle).angle_to(to)) < deg_to_rad(t.b * 0.5) + 0.3:
					return to.normalized()
	return Vector2.ZERO


func _ally_hurt(p: Player) -> bool:
	for a in Combat.players():
		if a.hp / a.max_hp < 0.7:
			return true
	return false


func _use_skills(p: Player, def: Dictionary, target: Enemy, near: int, boss_near: bool, mm: MatchManager, in_kitchen: bool) -> void:
	for slot in [2, 1]:
		var s: Dictionary = def["skill%d" % slot]
		if p.cd[slot] > 0.0:
			continue
		var go := false
		match s.kind:
			"heal_ally":
				go = _ally_hurt(p)
			"team_buff":
				go = near >= 3 or boss_near
			"dome":
				go = in_kitchen and near >= 3 and mm.table.food_pct() < 0.75
			"taunt_shield":
				go = near >= 2
			"buff_self":
				go = target != null
			"tp_crit":
				go = target != null and p.global_position.distance_to(target.global_position) > 120.0
			"aoe", "vortex", "volley", "flurry", "trap":
				go = near >= 3 or boss_near
			_:   # cone, line, zone, dash_zone
				go = near >= 1
		if go:
			var at: Vector2 = target.global_position if target else p.global_position
			Skills.cast(p, slot, p.aim, at)
