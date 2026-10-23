class_name Enemy
extends CharacterBody2D
## Pest AI. Runs ONLY on the server; position/hp/face are replicated to clients.
## Behaviour loop:  CHASE -> (pick attack) -> TELEGRAPH -> STRIKE -> RECOVER -> CHASE
## Telegraph length comes from the difficulty (1.2s / 0.9s / 0.7s).

signal died(enemy: Enemy)

enum State { CHASE, TELEGRAPH, STRIKE, RECOVER }

const KITCHEN_MIN := Vector2(40, 40)
const KITCHEN_MAX := Vector2(1240, 680)

var key := "forager_ant"
var data: Dictionary = {}
var diff: Dictionary = {}
var wave := 1
var is_yard := false
var is_miniboss := false
var ether := 0

var hp := 1.0
var max_hp := 1.0
var atk := 10.0
var speed := 70.0
var radius := 12.0
var face := Vector2.LEFT
var state := State.CHASE
var dead := false
var phase2 := false

var armor_shred := 0.0        # +x% damage taken
var stun_until := 0.0
var root_until := 0.0
var slow := 0.0
var slow_until := 0.0
var taunt_target: Player = null
var taunt_until := 0.0
var last_src: Node = null     # who last damaged us (kill credit for on-kill item effects)
var marked_until := 0.0       # Laser Pointer mark
var poison_stacks := 0
var poison_dps := 0.0
var poison_until := 0.0
var poison_src: Node = null
var heavy_hit := false        # true while performing a heavy (telegraphed) attack

var target: Node2D = null
var _token := 0               # bumped to cancel an in-flight attack coroutine (stun etc.)
var _cd_until := {}
var _tele := {}


func setup(d: Dictionary) -> void:
	key = d.key
	wave = d.wave
	is_yard = d.yard
	diff = GameData.DIFFICULTY[d.diff]
	data = GameData.ENEMIES[key]
	name = "E%d" % d.uid
	var elite: bool = d.get("elite", false)
	var mult := 1.5 if elite else 1.0
	max_hp = GameData.enemy_hp(key, wave) * diff.hp * mult
	hp = max_hp
	atk = float(data.atk) * diff.atk * mult
	speed = data.speed
	radius = data.radius * (1.2 if elite else 1.0)
	ether = data.ether
	is_miniboss = data.get("miniboss", false)
	position = d.pos


func _ready() -> void:
	add_to_group("enemies")
	collision_layer = 2
	collision_mask = 0   # draft: no collisions; add steering/separation later
	var rc := SceneReplicationConfig.new()
	for prop in [^".:position", ^".:face", ^".:hp"]:
		rc.add_property(prop)
		rc.property_set_spawn(prop, true)
		rc.property_set_replication_mode(prop, SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	var sync := MultiplayerSynchronizer.new()
	sync.name = "Sync"
	sync.replication_config = rc
	add_child(sync)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _table() -> DiningTable:
	return get_tree().get_first_node_in_group("table") as DiningTable


func _attacks() -> Array:
	return data.attacks_p2 if phase2 else data.attacks


# ================================================================== DEFENSE (taking damage)
func server_damage(amount: float, _src: Node = null) -> void:
	if dead:
		return
	if _src != null and is_instance_valid(_src):
		last_src = _src
	if data.get("block", 0.0) > 0.0 and _src is Node2D:
		var to_src: Vector2 = (_src.global_position - global_position).normalized()
		if to_src.dot(face) > 0.5:      # Shield Ant: frontal block
			amount *= 1.0 - data.block
	amount *= 1.0 + armor_shred
	hp -= amount
	if key == "trash_king" and not phase2 and hp <= max_hp * 0.5 and hp > 0.0:
		phase2 = true
		_token += 1
		_run_attack({"kind": "leap", "range": 0.0, "cd": 0.0})
	if hp <= 0.0:
		dead = true
		died.emit(self)
		queue_free()


func apply_stun(t: float) -> void:
	if data.get("boss", false):
		return
	stun_until = maxf(stun_until, _now() + t)
	_token += 1
	state = State.CHASE


func apply_root(t: float) -> void:
	if data.get("boss", false):
		return
	root_until = maxf(root_until, _now() + t)


func apply_slow(pct: float, t: float) -> void:
	slow = maxf(slow, pct)
	slow_until = maxf(slow_until, _now() + t)


func add_poison(dps_per_stack: float, dur: float, max_stacks: int, src: Node) -> void:
	poison_stacks = mini(poison_stacks + 1, max_stacks)
	poison_dps = maxf(poison_dps, dps_per_stack)
	poison_until = _now() + dur
	poison_src = src


func taunt(p: Player, t: float) -> void:
	taunt_target = p
	taunt_until = _now() + t


# ================================================================== BEHAVIOUR
func _physics_process(delta: float) -> void:
	queue_redraw()
	if not multiplayer.is_server() or dead:
		return
	var now := _now()
	if now >= slow_until:
		slow = 0.0
	if poison_stacks > 0:
		if now >= poison_until:
			poison_stacks = 0
		else:
			server_damage(poison_stacks * poison_dps * delta, poison_src)
			if dead:
				return
	if now < stun_until:
		return
	if phase2 and key == "trash_king":
		var tb := _table()
		if tb and state == State.CHASE:
			tb.take_damage(float(data.eat_dps) * delta)   # eats the food directly
	if state == State.CHASE:
		_chase(delta, now)


func _pick_target(now: float) -> Node2D:
	if taunt_target and is_instance_valid(taunt_target) and not taunt_target.dead and now < taunt_until:
		return taunt_target
	var best: Player = null
	var best_d := 400.0 if is_yard else 150.0   # indoor pests ignore players unless close
	for p in get_tree().get_nodes_in_group("players"):
		if p.dead or p.untargetable:
			continue
		var d: float = p.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = p
	if best:
		return best
	return null if is_yard else _table()


func _target_radius(t: Node2D) -> float:
	return t.radius if t is DiningTable else 12.0


func _chase(delta: float, now: float) -> void:
	target = _pick_target(now)
	if target == null:
		return
	var to := target.global_position - global_position
	var dir := to.normalized()
	var edge := to.length() - _target_radius(target)
	face = face.lerp(dir, 0.35).normalized() if face.lerp(dir, 0.35).length() > 0.01 else dir
	if _try_attack(edge, now):
		return
	if now < root_until:
		return
	var keep: float = data.get("keep", 0.0)
	if keep > 0.0:
		if edge < keep - 20.0:
			dir = -dir * 0.6
		elif edge <= keep + 20.0:
			return
	elif edge <= 8.0:
		return
	var spd := speed * (1.0 - slow)
	global_position += dir * spd * delta
	global_position = global_position.clamp(Vector2(-99999, -99999), Vector2(99999, 99999))


func _try_attack(edge: float, now: float) -> bool:
	var options: Array = []
	for a in _attacks():
		if now >= _cd_until.get(a.kind, 0.0) and edge <= a.range:
			options.append(a)
	if options.is_empty():
		return false
	var a: Dictionary = options.pick_random()
	_cd_until[a.kind] = now + a.cd
	_run_attack(a)
	return true


func _valid(token: int) -> bool:
	return token == _token and not dead and is_inside_tree()


func _wait(t: float, token: int) -> bool:
	await get_tree().create_timer(t).timeout
	return _valid(token)


# ---- one attack = telegraph -> strike -> recover (coroutine; cancelled by _token)
func _run_attack(a: Dictionary) -> void:
	var token := _token
	state = State.TELEGRAPH
	var t: float = diff.telegraph
	var tgt := target if (target != null and is_instance_valid(target)) else _table()
	var origin := global_position
	var dir := (tgt.global_position - origin).normalized() if tgt else face
	face = dir
	var dmg: float = atk * float(a.get("mult", 1.0))
	heavy_hit = a.kind != "bite"

	match a.kind:
		"bite":
			if not await _wait(0.2, token): return
			state = State.STRIKE
			if tgt and is_instance_valid(tgt) and global_position.distance_to(tgt.global_position) - _target_radius(tgt) <= a.range + 10.0:
				_hurt(tgt, dmg)

		"dash":   # Sprinter Roach – red line, then a fast dash that knocks back
			rpc("net_tele", "line", origin, dir.angle(), a.dist, 36.0, t)
			if not await _wait(t, token): return
			await _dash(dir, a.dist, 520.0, dmg, true, 30.0)

		"dive":   # Fencer Fly – red circle on target, 3 quick slashes
			var spot := tgt.global_position if tgt else origin
			rpc("net_tele", "circle", spot, 0.0, a.radius, 0.0, t)
			if not await _wait(t, token): return
			state = State.STRIKE
			global_position = spot
			for i in int(a.hits):
				_strike_circle(spot, a.radius, dmg)
				if not await _wait(0.2, token): return

		"bash":   # Shield Ant – red cone, stun
			rpc("net_tele", "cone", origin, dir.angle(), a.range, a.arc, t)
			if not await _wait(t, token): return
			state = State.STRIKE
			_strike_cone(origin, dir, a.range, a.arc, dmg, a.stun)

		"slam":   # Gutter Rat – large red ring, leaves a slow zone
			rpc("net_tele", "circle", origin, 0.0, a.radius, 0.0, t)
			if not await _wait(t, token): return
			state = State.STRIKE
			_strike_circle(origin, a.radius, dmg)
			Combat.enemy_zone(origin, a.radius, 0.0, 4.0, 0.4)

		"lob":   # Maggot Mortar – yellow ! + green ring, acid puddle (15 dps)
			var spot := tgt.global_position if tgt else origin
			rpc("net_tele", "acid", spot, 0.0, a.puddle_radius, 0.0, t)
			if not await _wait(t, token): return
			state = State.STRIKE
			Combat.enemy_zone(spot, a.puddle_radius, a.puddle_dps, 5.0)

		"drift":   # Sir Roachalot – multi-lane charges across the kitchen
			for i in int(a.lanes):
				var lane_y := _pick_lane_y()
				var from_left := randf() < 0.5
				var start := Vector2(60.0 if from_left else 1220.0, lane_y)
				var d := Vector2.RIGHT if from_left else Vector2.LEFT
				rpc("net_tele", "line", start, d.angle(), 1160.0, 56.0, t)
				global_position = start
				face = d
				if not await _wait(t, token): return
				await _dash(d, 1160.0, 900.0, dmg, true, 40.0)
				if not await _wait(0.3, token): return

		"forks":   # Ratatouille – boomerang forks (hits out and back)
			var end: Vector2 = origin + dir * float(a.length)
			rpc("net_tele", "line", origin, dir.angle(), a.length, 40.0, t)
			if not await _wait(t, token): return
			state = State.STRIKE
			_strike_line(origin, end, 40.0, dmg)
			if not await _wait(0.6, token): return
			_strike_line(origin, end, 40.0, dmg)

		"cleave":   # Ratatouille – 360 degree cleave
			rpc("net_tele", "circle", origin, 0.0, a.radius, 0.0, t)
			if not await _wait(t, token): return
			state = State.STRIKE
			_strike_circle(origin, a.radius, dmg)

		"summon":   # Trash King phase 1 – vent swarm
			rpc("net_tele", "circle", origin, 0.0, 90.0, 0.0, t)
			if not await _wait(t, token): return
			var mm := get_tree().get_first_node_in_group("match") as MatchManager
			if mm:
				mm.spawn_adds(6)

		"garbage":   # Trash King phase 1 – garbage wave
			rpc("net_tele", "line", origin, dir.angle(), 700.0, 70.0, t)
			if not await _wait(t, token): return
			state = State.STRIKE
			_strike_line(origin, origin + dir * 700.0, 70.0, dmg)

		"leap":   # Trash King phase 2 – leaps onto the dining table
			var tb := _table()
			var spot := tb.global_position if tb else origin
			rpc("net_tele", "circle", spot, 0.0, 130.0, 0.0, t)
			if not await _wait(t, token): return
			global_position = spot
			_strike_circle(spot, 130.0, atk * 1.5)

		"shock":   # Trash King phase 2 – ring shockwaves
			for i in 2:
				rpc("net_tele", "circle", global_position, 0.0, 120.0 + 60.0 * i, 0.0, t)
				if not await _wait(t, token): return
				state = State.STRIKE
				_strike_circle(global_position, 120.0 + 60.0 * i, dmg)

	if not _valid(token):
		return
	state = State.RECOVER
	if await _wait(a.get("recover", 0.5), token):
		state = State.CHASE


func _pick_lane_y() -> float:
	var ps := Combat.players()
	if ps.is_empty():
		return randf_range(120.0, 600.0)
	return ps.pick_random().global_position.y


# ---- damage dealt BY the enemy (shared hit helpers)
func _hurt(t: Node, amount: float) -> void:
	if t is Player:
		t.server_damage(amount, self)
	elif t is DiningTable:
		t.take_damage(amount)


func _strike_circle(c: Vector2, r: float, dmg: float, stun: float = 0.0) -> void:
	for p in Combat.players():
		if p.global_position.distance_to(c) <= r + 12.0:
			p.server_damage(dmg, self)
			if stun > 0.0:
				p.apply_stun(stun)
	var tb := _table()
	if tb and tb.global_position.distance_to(c) <= r + tb.radius:
		tb.take_damage(dmg)


func _strike_cone(o: Vector2, dir: Vector2, length: float, arc_deg: float, dmg: float, stun: float) -> void:
	var half := deg_to_rad(arc_deg * 0.5)
	for p in Combat.players():
		var to: Vector2 = p.global_position - o
		if to.length() <= length + 12.0 and absf(dir.angle_to(to)) <= half:
			p.server_damage(dmg, self)
			if stun > 0.0:
				p.apply_stun(stun)
	var tb := _table()
	if tb:
		var to_t := tb.global_position - o
		if to_t.length() <= length + tb.radius and absf(dir.angle_to(to_t)) <= half:
			tb.take_damage(dmg)


func _strike_line(a: Vector2, b: Vector2, width: float, dmg: float) -> void:
	for p in Combat.players():
		if Combat.seg_dist(p.global_position, a, b) <= width * 0.5 + 12.0:
			p.server_damage(dmg, self)
	var tb := _table()
	if tb and Combat.seg_dist(tb.global_position, a, b) <= width * 0.5 + tb.radius:
		tb.take_damage(dmg)


func _dash(dir: Vector2, dist: float, spd: float, dmg: float, knock: bool, width: float) -> void:
	state = State.STRIKE
	var travelled := 0.0
	var hit := {}
	while travelled < dist and not dead:
		await get_tree().physics_frame
		if dead:
			return
		var step := spd * get_physics_process_delta_time()
		global_position += dir * step
		travelled += step
		for p in Combat.players():
			if not hit.has(p) and p.global_position.distance_to(global_position) <= width:
				hit[p] = true
				p.server_damage(dmg, self)
				if knock:
					p.rpc("net_teleport", p.global_position + dir * 70.0)
		var tb := _table()
		if tb and not hit.has(tb) and tb.global_position.distance_to(global_position) <= tb.radius + width:
			hit[tb] = true
			tb.take_damage(dmg)


# ================================================================== TELEGRAPH (all peers draw)
@rpc("authority", "call_local", "reliable")
func net_tele(shape: String, pos: Vector2, angle: float, a: float, b: float, dur: float) -> void:
	_tele = {"shape": shape, "pos": pos, "angle": angle, "a": a, "b": b, "t0": _now(), "dur": maxf(dur, 0.05)}


func _draw() -> void:
	var col: Color = data.get("color", Color.WHITE) if not data.is_empty() else Color.WHITE
	if _tele.size() > 0:
		var prog: float = (_now() - float(_tele.t0)) / float(_tele.dur)
		if prog > 1.1:
			_tele = {}
		else:
			_draw_tele(clampf(prog, 0.0, 1.0))
	draw_circle(Vector2.ZERO, radius, col)
	draw_line(Vector2.ZERO, face * (radius + 6.0), Color.WHITE, 2.0)
	if hp < max_hp:
		var w := radius * 2.4
		draw_rect(Rect2(-w / 2, -radius - 10, w, 3), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w / 2, -radius - 10, w * clampf(hp / max_hp, 0.0, 1.0), 3), Color.RED)


func _draw_tele(prog: float) -> void:
	var red := Color(1.0, 0.15, 0.15)
	var fill := Color(red.r, red.g, red.b, 0.15 + 0.4 * prog)
	var line := Color(red.r, red.g, red.b, 0.9)
	var o := to_local(_tele.pos)
	match _tele.shape:
		"line":
			var d := Vector2.from_angle(_tele.angle)
			var n: Vector2 = d.orthogonal() * float(_tele.b) * 0.5
			var len: float = _tele.a
			draw_colored_polygon(PackedVector2Array([o + n, o + d * len + n, o + d * len - n, o - n]), fill)
		"circle":
			draw_circle(o, _tele.a, fill)
			draw_arc(o, _tele.a, 0.0, TAU, 40, line, 2.0)
		"acid":
			var g := Color(0.5, 0.9, 0.2, 0.2 + 0.4 * prog)
			draw_circle(o, _tele.a, g)
			draw_arc(o, _tele.a, 0.0, TAU, 40, Color(0.4, 1.0, 0.2), 2.0)
			draw_string(ThemeDB.fallback_font, o + Vector2(-4, -_tele.a - 4), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.YELLOW)
		"cone":
			var pts := PackedVector2Array([o])
			var half := deg_to_rad(_tele.b * 0.5)
			for i in 13:
				pts.append(o + Vector2.from_angle(_tele.angle - half + (half * 2.0) * i / 12.0) * _tele.a)
			draw_colored_polygon(pts, fill)
