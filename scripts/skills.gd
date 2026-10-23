class_name Skills
extends RefCounted
## Character BEHAVIOUR. Every skill in GameData.CHARACTERS has a "kind"; this file
## maps each kind to an effect. New character = new data entry (+ a new kind only
## if the mechanic is truly unique). SERVER-ONLY.
##
## kinds: buff_self, aoe, cone, line, zone, dash_zone, volley, vortex, dome,
##        tp_crit, flurry, taunt_shield, heal_ally, team_buff, trap

static func cast(p: Player, slot: int, aim: Vector2, mouse: Vector2) -> void:
	if p.dead or p.cd[slot] > 0.0:
		return
	var def: Dictionary = GameData.CHARACTERS[p.char_id]["skill%d" % slot]
	p.cd[slot] = def.cd * (1.0 - p.cdr())
	if p.has_item("overclocked_igniter"):
		p.empowered = true                    # next basic attack deals +50%
	var pos := p.global_position
	var dmg := p.skill_dmg(def.get("base", 0.0), def.get("coef", 0.0))
	var target := pos + (mouse - pos).limit_length(def.get("range", 0.0))

	match def.kind:
		"buff_self":
			p.add_buff(def.name, def.mods, def.dur)
			p.rpc("net_fx", pos, 50.0)

		"aoe":
			p.rpc("net_fx", pos, def.radius)
			Combat.circle(pos, def.radius, dmg, p, def)

		"cone":
			p.rpc("net_fx", pos + aim * def.range * 0.5, def.range * 0.5)
			Combat.cone(pos, aim, def.range, def.arc, dmg, p, def)

		"line":
			p.rpc("net_fx", pos + aim * def.length * 0.5, def.width)
			Combat.line(pos, aim, def.length, def.width, dmg, p, def)

		"zone":   # Suds / Clank / Flick / Goo patch
			p.rpc("net_fx", target, def.radius)
			if def.get("burst", 0.0) > 0.0:
				Combat.circle(target, def.radius, p.skill_dmg(def.burst, 0.0), p, {})
			Combat.zone(target, def.radius, def.dps, def.dur, p, def)

		"dash_zone":   # Pip (dash back + smoke) / Flick (dash fwd + fire trail)
			var dest := pos + aim * def.dash
			p.rpc("net_teleport", dest)
			var zc := pos.lerp(dest, def.zone_offset)
			p.rpc("net_fx", zc, def.radius)
			Combat.zone(zc, def.radius, def.dps, def.dur, p, def)

		"volley":   # Pip ultimate: N pulses around the player
			for i in int(def.waves):
				if p.dead:
					break
				p.rpc("net_fx", p.global_position, def.radius)
				Combat.circle(p.global_position, def.radius, dmg, p, def)
				await Combat.wait(def.dur / def.waves)

		"vortex":   # Broomsworth ultimate: pull + DoT + projectile deflect
			p.deflecting = true
			var t := 0.0
			while t < def.dur and not p.dead:
				await Combat.wait(0.25)
				t += 0.25
				p.rpc("net_fx", p.global_position, def.radius)
				for e in Combat.enemies():
					if e.global_position.distance_to(p.global_position) <= def.radius:
						if not e.data.get("boss", false):
							e.global_position = e.global_position.move_toward(p.global_position, 40.0)
						Combat.hit(e, def.dps * 0.25, p, {"can_crit": false})
			p.deflecting = false

		"dome":   # Suds ultimate: table + allies inside are immune, then pop
			var table := p.get_tree().get_first_node_in_group("table") as DiningTable
			var c: Vector2 = table.global_position if table else pos
			if table:
				table.invulnerable = true
			var t := 0.0
			while t < def.dur:
				await Combat.wait(0.25)
				t += 0.25
				p.rpc("net_fx", c, def.radius)
				for pl in Combat.players():
					pl.invulnerable = pl.global_position.distance_to(c) <= def.radius
			for pl in p.get_tree().get_nodes_in_group("players"):
				pl.invulnerable = false
			if table:
				table.invulnerable = false
			Combat.circle(c, def.radius, p.skill_dmg(def.pop, 0.0), p, {})

		"tp_crit":   # Skewer: blink behind the tankiest nearby pest, next N hits crit
			var best: Enemy = null
			for e in Combat.enemies():
				if e.global_position.distance_to(pos) <= def.range and (best == null or e.hp > best.hp):
					best = e
			if best == null:
				p.cd[slot] = 0.5   # no target -> refund
				return
			p.rpc("net_teleport", best.global_position - best.face * 36.0)
			p.next_crits = def.crits

		"flurry":   # Skewer ultimate: untargetable multi-slash
			p.untargetable = true
			var n: int = def.hits
			for i in n:
				if p.dead:
					break
				p.rpc("net_fx", p.global_position, def.radius)
				Combat.circle(p.global_position, def.radius, p.stat("atk") * def.atk_coef, p, {})
				await Combat.wait(def.dur / n)
			p.untargetable = false

		"taunt_shield":   # Clank
			p.add_shield(def.shield, def.dur)
			p.rpc("net_fx", pos, def.radius)
			for e in Combat.enemies():
				if e.global_position.distance_to(pos) <= def.radius:
					e.taunt(p, def.dur)

		"heal_ally":   # Whisker
			var best: Player = null
			for a in Combat.players():
				if a == p:
					continue
				if best == null or a.hp / a.max_hp < best.hp / best.max_hp:
					best = a
			if best == null:
				best = p
			best.heal(dmg)
			best.add_buff(def.name, def.mods, def.dur)
			p.rpc("net_fx", best.global_position, 40.0)

		"team_buff":   # Whisker ultimate
			for a in Combat.players():
				a.add_buff(def.name, def.mods, def.dur)
			p.rpc("net_fx", pos, 160.0)

		"trap":   # Goo ultimate: giant mousetrap snaps N times
			p.rpc("net_fx", target, def.radius)
			for i in int(def.snaps):
				await Combat.wait(def.interval)
				p.rpc("net_fx", target, def.radius)
				Combat.circle(target, def.radius, dmg, p, {})
