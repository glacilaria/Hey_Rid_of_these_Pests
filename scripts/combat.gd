class_name Combat
extends RefCounted
## ATTACK side. Static, SERVER-ONLY helpers that find enemies in a shape and
## apply damage + status effects. Players never damage enemies directly –
## they ask the server (Player.srv_attack / srv_skill) and the server calls this.

static func _tree() -> SceneTree:
	return Engine.get_main_loop() as SceneTree


static func wait(t: float) -> void:
	await _tree().create_timer(t).timeout


static func enemies() -> Array:
	return _tree().get_nodes_in_group("enemies").filter(func(e): return not e.dead)


static func players() -> Array:
	return _tree().get_nodes_in_group("players").filter(func(p): return not p.dead)


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Single hit with crit roll, lifesteal and status effects.
static func hit(e: Enemy, dmg: float, src, opts: Dictionary = {}, origin: Vector2 = Vector2.ZERO) -> void:
	if e == null or e.dead:
		return
	var final := dmg
	var crit := false
	var valid_src: bool = src != null and is_instance_valid(src)
	if valid_src and opts.get("can_crit", true):
		var cr: float = 1.0 if opts.get("force_crit", false) else src.crit_rate()
		if e.marked_until > Time.get_ticks_msec() / 1000.0:
			cr += 0.05                                   # Laser Pointer mark helps ALL allies
		if randf() < cr:
			final *= src.crit_dmg()
			crit = true
	e.server_damage(final, src if valid_src else null)
	if valid_src:
		var ls: float = src.bonus("lifesteal")
		if ls > 0.0:
			src.heal(final * ls)
		src.on_hit(e, final, crit, opts.get("basic", false))   # item passives
	apply_opts(e, opts, origin)


static func apply_opts(e: Enemy, o: Dictionary, origin: Vector2) -> void:
	if e.dead:
		return
	if o.get("stun", 0.0) > 0.0:
		e.apply_stun(o.stun)
	if o.get("slow", 0.0) > 0.0:
		e.apply_slow(o.slow, o.get("slow_dur", 3.0))
	if o.get("root", 0.0) > 0.0:
		e.apply_root(o.root)
	if o.get("pin", 0.0) > 0.0:
		e.apply_root(o.pin)
	if o.get("shred", 0.0) > 0.0:
		e.armor_shred = maxf(e.armor_shred, o.shred)   # shred = +x% damage taken
	if o.get("push", 0.0) > 0.0 and not e.data.get("boss", false):
		e.global_position += (e.global_position - origin).normalized() * o.push


static func circle(pos: Vector2, radius: float, dmg: float, src, opts: Dictionary = {}) -> void:
	for e in enemies():
		if e.global_position.distance_to(pos) <= radius + e.radius:
			hit(e, dmg, src, opts, pos)


static func cone(origin: Vector2, dir: Vector2, length: float, arc_deg: float, dmg: float, src, opts: Dictionary = {}) -> void:
	var half := deg_to_rad(arc_deg * 0.5)
	for e in enemies():
		var to: Vector2 = e.global_position - origin
		if to.length() <= length + e.radius and absf(dir.angle_to(to)) <= half:
			hit(e, dmg, src, opts, origin)


static func line(origin: Vector2, dir: Vector2, length: float, width: float, dmg: float, src, opts: Dictionary = {}) -> void:
	var end := origin + dir * length
	for e in enemies():
		if seg_dist(e.global_position, origin, end) <= width * 0.5 + e.radius:
			hit(e, dmg, src, opts, origin)


## Ground zone that ticks twice per second (damage-over-time, slows, roots).
static func zone(center: Vector2, radius: float, dps: float, dur: float, src, opts: Dictionary = {}) -> void:
	var t := 0.0
	var rooted := {}
	var max_targets: int = opts.get("max_targets", 9999)
	while t < dur:
		await wait(0.5)
		t += 0.5
		for e in enemies():
			if e.global_position.distance_to(center) > radius + e.radius:
				continue
			var tick := {"can_crit": false}
			if opts.get("slow", 0.0) > 0.0:
				tick["slow"] = opts.slow
				tick["slow_dur"] = 0.8
			if opts.get("root", 0.0) > 0.0 and not rooted.has(e) and rooted.size() < max_targets:
				rooted[e] = true
				tick["root"] = opts.root
			if dps > 0.0:
				hit(e, dps * 0.5, src, tick, center)
			else:
				apply_opts(e, tick, center)
		if opts.get("ally_spd", 0.0) > 0.0:
			for p in players():
				if p.global_position.distance_to(center) <= radius:
					p.add_buff("slippery_floor", {"spd": opts.ally_spd}, 0.8)


## Enemy-owned puddle / slow zone: hurts players and the dining table.
static func enemy_zone(center: Vector2, radius: float, dps: float, dur: float, slow: float = 0.0) -> void:
	var t := 0.0
	while t < dur:
		await wait(0.5)
		t += 0.5
		for p in players():
			if p.global_position.distance_to(center) <= radius + 12.0:
				if dps > 0.0:
					p.server_damage(dps * 0.5, null)
				if slow > 0.0:
					p.add_buff("enemy_slow", {"spd": -slow}, 0.8)
		var tb = _tree().get_first_node_in_group("table")
		if tb and dps > 0.0 and tb.global_position.distance_to(center) <= radius + tb.radius:
			tb.take_damage(dps * 0.5)
