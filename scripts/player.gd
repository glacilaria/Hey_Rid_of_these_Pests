class_name Player
extends CharacterBody2D
## One defender. The OWNING peer controls movement + aim (authority).
## The SERVER resolves attacks, skills, damage, HP, buffs and death.

signal died(player: Player)

const SEND_INTERVAL := 0.05

var peer_id := 1
var char_id := "nanay_tala"
var level := 1
var base: Dictionary = {}
var item_flat: Dictionary = {}   # filled from Items.total_mods() on every inventory change, e.g. {"atk": 15.0, "hp": 180.0}
var item_pct: Dictionary = {}    # same, for the % stats e.g. {"aspd": 0.15, "spd": 0.10, "skill_power": 0.18}

var hp := 1.0
var max_hp := 1.0
var shield := 0.0
var shield_until := 0.0
var dead := false
var invulnerable := false     # Mega Bubble Dome
var untargetable := false     # Thousand Hors d'Oeuvres
var deflecting := false       # Whirlwind Cleanse (hook for projectile deflect)
var damage_reduction := 0.0

var aim := Vector2.RIGHT
var move_mult := 1.0
var stun_until := 0.0

var cd := {1: 0.0, 2: 0.0}          # seconds left on skill 1 / 2 (server is the source of truth)
var cd_max := {1: 1.0, 2: 1.0}      # length of the cooldown that is currently running (for the HUD circles)
var atk_cd := 0.0
var next_crits := 0
var attack_count := 0
var buffs := {}               # name -> {mods: Dictionary, until: float}

var inventory: Array = []     # item ids (see items.gd), max 6
var is_bot := false
var brain: BotBrain
var empowered := false        # Overclocked Igniter: next basic is +50%
var _static := 0.0            # Roller-Slippers charge
var _static_ready := false
var _mitt_icd := 0.0
var _last_pos := Vector2.ZERO

var _send_t := 0.0
var _fx: Array = []


func setup(d: Dictionary) -> void:
	peer_id = d.peer
	char_id = d.char_id
	level = d.level
	base = GameData.build_stats(char_id, level)
	max_hp = base.hp
	hp = max_hp
	is_bot = d.get("bot", false)
	if is_bot:
		brain = BotBrain.new()
	name = str(peer_id)


func _ready() -> void:
	add_to_group("players")
	collision_layer = 1
	collision_mask = 0   # draft: no body collisions; add walls/obstacles later
	var rc := SceneReplicationConfig.new()
	for prop in [^".:position", ^".:aim"]:
		rc.add_property(prop)
		rc.property_set_spawn(prop, true)
		rc.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	$MultiplayerSynchronizer.replication_config = rc
	if is_multiplayer_authority() and not is_bot:
		var cam := Camera2D.new()
		add_child(cam)
		cam.make_current()


# ------------------------------------------------------------------ stats
func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


## Multiplicative stats (atk, hp, aspd, spd)
func stat(key: String) -> float:
	var add: float = item_pct.get(key, 0.0)
	for b in buffs.values():
		add += b.mods.get(key, 0.0)
	if key == "aspd":
		add = minf(add, 2.5)          # GDD: ASPD caps at +250%
	return (base.get(key, 0.0) + item_flat.get(key, 0.0)) * (1.0 + add)


## Additive stats (lifesteal, crit bonuses...)
func bonus(key: String) -> float:
	var add: float = item_pct.get(key, 0.0)
	for b in buffs.values():
		add += b.mods.get(key, 0.0)
	return add


func crit_rate() -> float:
	return clampf(base.crit_rate + item_flat.get("crit_rate", 0.0) + bonus("crit_rate"), 0.0, 1.0)


func crit_dmg() -> float:
	return base.crit_dmg + item_flat.get("crit_dmg", 0.0) + bonus("crit_dmg")


func cdr() -> float:
	return clampf(bonus("cdr"), 0.0, 0.5)


func skill_dmg(base_dmg: float, coef: float) -> float:
	return (base_dmg * base.skill_mult + coef * stat("atk")) * (1.0 + bonus("skill_power"))


# ------------------------------------------------------------------ frame loop
func _physics_process(delta: float) -> void:
	if is_bot:
		if multiplayer.is_server():
			brain.think(self, delta)
	elif is_multiplayer_authority() and not dead:
		_local_input(delta)
	if multiplayer.is_server():
		_server_tick(delta)
	else:
		cd[1] = maxf(0.0, cd[1] - delta)       # client mirror of the server's cooldowns (HUD only)
		cd[2] = maxf(0.0, cd[2] - delta)
	for f in _fx:
		f.t -= delta
	_fx = _fx.filter(func(f): return f.t > 0.0)
	queue_redraw()


func _local_input(delta: float) -> void:
	var stunned := _now() < stun_until
	var dir := Vector2.ZERO if stunned else Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = dir * base.spd * GameData.SPEED_SCALE * move_mult
	move_and_slide()
	aim = (get_global_mouse_position() - global_position).normalized()
	if stunned:
		return
	_send_t -= delta
	if Input.is_action_pressed("attack") and _send_t <= 0.0:
		_send_t = SEND_INTERVAL
		_to_server(&"srv_attack", [aim])
	if Input.is_action_just_pressed("skill_1"):
		_to_server(&"srv_skill", [1, aim, get_global_mouse_position()])
	if Input.is_action_just_pressed("skill_2"):
		_to_server(&"srv_skill", [2, aim, get_global_mouse_position()])


func _to_server(method: StringName, args: Array) -> void:
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


## SERVER: start (or replace) a skill cooldown and tell the owning player so the HUD circle follows it.
func start_cd(slot: int, secs: float) -> void:
	cd[slot] = secs
	cd_max[slot] = maxf(secs, 0.01)
	_push_cd()


func _push_cd() -> void:
	if is_bot:
		return
	if peer_id == multiplayer.get_unique_id():
		net_cd(cd[1], cd[2], cd_max[1], cd_max[2])          # host's own player: no network hop
	else:
		rpc_id(peer_id, "net_cd", cd[1], cd[2], cd_max[1], cd_max[2])


@rpc("any_peer", "call_local", "reliable")
func net_cd(left1: float, left2: float, max1: float, max2: float) -> void:
	if not _from_server():
		return
	cd = {1: left1, 2: left2}
	cd_max = {1: max1, 2: max2}


## 0.0 = just used, 1.0 = ready again (what the HUD circles show).
func cd_fill(slot: int) -> float:
	if cd[slot] <= 0.0:
		return 1.0
	return clampf(1.0 - cd[slot] / cd_max[slot], 0.0, 1.0)


func _server_tick(delta: float) -> void:
	_item_tick(delta)
	atk_cd = maxf(0.0, atk_cd - delta)
	cd[1] = maxf(0.0, cd[1] - delta)
	cd[2] = maxf(0.0, cd[2] - delta)
	var now := _now()
	var changed := false
	for k in buffs.keys():
		if now >= buffs[k].until:
			buffs.erase(k)
			changed = true
	if changed:
		_sync_move_mult()
	if shield > 0.0 and now >= shield_until:
		shield = 0.0
		rpc("net_hp", hp, max_hp, shield)


# ------------------------------------------------------------------ SERVER: attack
@rpc("any_peer", "unreliable_ordered")
func srv_attack(dir: Vector2) -> void:
	if not multiplayer.is_server() or not _from_owner() or dead or atk_cd > 0.0 or _now() < stun_until:
		return
	atk_cd = 1.0 / stat("aspd")
	aim = dir.normalized()
	attack_count += 1
	var def: Dictionary = GameData.CHARACTERS[char_id].attack
	var opts := {"basic": true}
	if next_crits > 0:
		next_crits -= 1
		opts["force_crit"] = true
	if has_item("snap_trap_gauntlet") and attack_count % 5 == 0:
		opts["force_crit"] = true                          # every 5th attack crits
	var dmg := stat("atk")
	if empowered and has_item("overclocked_igniter"):
		dmg *= 1.5
		empowered = false
	if has_item("cockroach_spray"):                       # aerosol cone replaces the basic attack shape
		Combat.cone(global_position, aim, 220.0, 70.0, dmg, self, opts)
		rpc("net_fx", global_position + aim * 110.0, 110.0)
	elif def.type == "melee":
		Combat.cone(global_position, aim, def.range, def.arc, dmg, self, opts)
		rpc("net_fx", global_position + aim * def.range * 0.5, def.range * 0.5)
	else:
		Combat.line(global_position, aim, def.range, def.width, dmg, self, opts)
		rpc("net_fx", global_position + aim * def.range, def.width)


@rpc("any_peer", "reliable")
func srv_skill(slot: int, dir: Vector2, mouse: Vector2) -> void:
	if not multiplayer.is_server() or not _from_owner() or _now() < stun_until:
		return
	Skills.cast(self, slot, dir.normalized(), mouse)


func _from_owner() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == 0 or s == peer_id


func _from_server() -> bool:
	var s := multiplayer.get_remote_sender_id()
	return s == 0 or s == 1


# ------------------------------------------------------------------ SERVER: defense / state
func server_damage(amount: float, _source: Node = null) -> void:
	if not multiplayer.is_server() or dead or invulnerable or untargetable:
		return
	amount *= 1.0 - damage_reduction
	if has_item("cast_iron_pot_lid") and _source is Enemy and _source.heavy_hit:
		amount *= 0.8                                       # -20% from heavy telegraphed hits
	if has_item("oven_mitt_armor") and _now() >= _mitt_icd:
		_mitt_icd = _now() + 1.0
		cd[1] = maxf(0.0, cd[1] - 0.5)
		cd[2] = maxf(0.0, cd[2] - 0.5)
		_push_cd()
	if shield > 0.0:
		var absorbed := minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
	hp = maxf(0.0, hp - amount)
	rpc("net_hp", hp, max_hp, shield)
	if hp <= 0.0:
		dead = true
		rpc("net_dead")
		died.emit(self)


func heal(amount: float) -> void:
	if not multiplayer.is_server() or dead:
		return
	hp = minf(max_hp, hp + amount)
	rpc("net_hp", hp, max_hp, shield)


func add_shield(amount: float, dur: float) -> void:
	shield = amount
	shield_until = _now() + dur
	rpc("net_hp", hp, max_hp, shield)


func add_buff(buff_name: String, mods: Dictionary, dur: float) -> void:
	buffs[buff_name] = {"mods": mods, "until": _now() + dur}
	_sync_move_mult()


func apply_stun(t: float) -> void:
	rpc("net_stun", t)


func server_revive(pct: float) -> void:
	dead = false
	invulnerable = false
	untargetable = false
	hp = max_hp * pct
	rpc("net_revive", hp, max_hp)


func _sync_move_mult() -> void:
	var m: float = stat("spd") / float(base.spd)
	if not is_equal_approx(m, move_mult):
		rpc("net_move_mult", m)


# ------------------------------------------------------------------ NET (server -> everyone)
@rpc("any_peer", "call_local", "reliable")
func net_hp(h: float, mh: float, sh: float) -> void:
	if _from_server():
		hp = h
		max_hp = mh
		shield = sh


@rpc("any_peer", "call_local", "reliable")
func net_dead() -> void:
	if _from_server():
		dead = true
		velocity = Vector2.ZERO


@rpc("any_peer", "call_local", "reliable")
func net_revive(h: float, mh: float) -> void:
	if _from_server():
		dead = false
		hp = h
		max_hp = mh


@rpc("any_peer", "call_local", "reliable")
func net_teleport(pos: Vector2) -> void:
	if _from_server():
		global_position = pos
		velocity = Vector2.ZERO


@rpc("any_peer", "call_local", "reliable")
func net_stun(t: float) -> void:
	if _from_server():
		stun_until = _now() + t


@rpc("any_peer", "call_local", "reliable")
func net_move_mult(m: float) -> void:
	if _from_server():
		move_mult = m


@rpc("any_peer", "call_local", "unreliable")
func net_fx(pos: Vector2, r: float) -> void:
	if _from_server():
		_fx.append({"pos": pos, "r": r, "t": 0.3})


# ------------------------------------------------------------------ ITEMS
func has_item(id: String) -> bool:
	return inventory.has(id)


## SERVER: replace the inventory and tell every peer.
func set_inventory(inv: Array) -> void:
	inventory = inv
	rpc("net_inventory", inv)
	_sync_move_mult()


@rpc("any_peer", "call_local", "reliable")
func net_inventory(inv: Array) -> void:
	if not _from_server():
		return
	inventory = inv
	var mods := Items.total_mods(inventory)
	item_flat = mods.flat
	item_pct = mods.pct
	var old_max := max_hp
	max_hp = stat("hp")
	if multiplayer.is_server() and not dead:
		hp = minf(max_hp, hp + maxf(0.0, max_hp - old_max))   # gained max HP is also healed
		rpc("net_hp", hp, max_hp, shield)


## Called by Combat.hit after every successful hit from this player.
func on_hit(e: Enemy, dmg: float, crit: bool, basic: bool) -> void:
	if e == null or e.dead:
		return
	if basic:
		if has_item("bug_spray"):
			e.add_poison(10.0, 3.0, 3, self)
		if has_item("cockroach_spray"):
			e.add_poison(15.0, 3.0, 8, self)
			e.armor_shred = maxf(e.armor_shred, 0.25)
		if has_item("laser_pointer"):
			e.marked_until = _now() + 4.0
		if _static_ready:
			_static_ready = false
			_static = 0.0
			Combat.hit(e, 40.0, self, {"can_crit": false})
	if crit:
		if has_item("electric_flyswatter") or has_item("high_voltage_zapper"):
			e.server_damage(25.0, self)                    # lightning shock
		if has_item("high_voltage_zapper"):
			var n := 0
			for x in Combat.enemies():
				if x != e and x.global_position.distance_to(e.global_position) <= 150.0:
					Combat.hit(x, dmg * 0.6, self, {"can_crit": false})
					n += 1
					if n >= 4:
						break
		if has_item("tungsten_slipper") and not e.dead:
			var extra := e.hp * 0.08
			if e.data.get("boss", false):
				extra = minf(extra, 150.0)
			e.server_damage(extra, self)
			e.apply_stun(0.2)


func on_kill() -> void:
	if has_item("caffeine_syringe"):
		if not buffs.has("caffeine_1"):
			add_buff("caffeine_1", {"aspd": 0.15}, 3.0)
		elif not buffs.has("caffeine_2"):
			add_buff("caffeine_2", {"aspd": 0.15}, 3.0)
		else:
			add_buff("caffeine_1", {"aspd": 0.15}, 3.0)


func _item_tick(delta: float) -> void:
	if inventory.is_empty():
		_last_pos = global_position
		return
	if has_item("roller_slippers") and not _static_ready:
		var moved := minf(global_position.distance_to(_last_pos), 40.0)
		_static += moved * 0.5
		if _static >= 100.0:
			_static_ready = true
	_last_pos = global_position
	if has_item("sub_zero_fridge_door") and not dead:
		heal(max_hp * 0.015 * delta)                       # frost aura regen
		for e in Combat.enemies():
			if e.global_position.distance_to(global_position) <= 128.0:
				e.apply_slow(0.3, 0.4)
	if has_item("turbo_vacuum_boots") and not dead:
		for a in Combat.players():
			if a != self and a.global_position.distance_to(global_position) <= 120.0:
				a.add_buff("slipstream", {"spd": 0.15}, 0.5)


# ------------------------------------------------------------------ placeholder art
func _draw() -> void:
	var def: Dictionary = GameData.CHARACTERS[char_id]
	var c: Color = def.color
	if dead:
		c = Color(0.4, 0.4, 0.4, 0.6)
	elif untargetable:
		c.a = 0.4
	draw_circle(Vector2.ZERO, 14.0, c)
	draw_line(Vector2.ZERO, aim * 22.0, Color.WHITE, 2.0)
	var w := 38.0
	draw_rect(Rect2(-w / 2, -28, w, 4), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-w / 2, -28, w * clampf(hp / max_hp, 0.0, 1.0), 4), Color.LIME_GREEN)
	if shield > 0.0:
		draw_rect(Rect2(-w / 2, -33, w * minf(1.0, shield / max_hp), 3), Color.CYAN)
	draw_string(ThemeDB.fallback_font, Vector2(-w / 2, -38), "%s%s" % [def.name, " [DOWN]" if dead else ""],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
	for f in _fx:
		draw_arc(to_local(f.pos), f.r, 0.0, TAU, 32, Color(1, 1, 1, f.t / 0.3), 2.0)
