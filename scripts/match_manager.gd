class_name MatchManager
extends Node2D
## THE GAME LOOP. Attach to the root of scenes/match.tscn.
## Server-authoritative: only the host runs _run_match(); clients just receive
## phase/timer/wallet/result RPCs and see replicated players + enemies.
##
##   for wave in 1..5:
##       YARD (60s) -> SUMMON -> KITCHEN_PREP (10s) -> SIEGE (3 sub-waves + miniboss)
##                  -> FEAST (revive, eat, rewards)         [wave 5: + Trash King -> VICTORY]

enum Phase { LOADING, YARD, KITCHEN_PREP, SIEGE, FEAST, VICTORY, DEFEAT }

const PLAYER_SCENE := preload("res://scenes/player.tscn")
const ENEMY_SCENE := preload("res://scenes/enemy.tscn")

const KITCHEN_CENTER := Vector2(640, 360)
const YARD_RECT := Rect2(2400, 0, 1280, 720)     # yard lives to the right of the kitchen
const YARD_ENTRANCE := Vector2(2440, 360)
const YARD_PEST_CAP := 18
const FEAST_TIME := 5.0

@onready var players_root: Node2D = $Players
@onready var enemies_root: Node2D = $Enemies
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var enemy_spawner: MultiplayerSpawner = $EnemySpawner
@onready var table: DiningTable = $Kitchen/DiningTable
@onready var vectors := {"left": $Kitchen/SpawnLeft, "top": $Kitchen/SpawnTop, "bottom": $Kitchen/SpawnBottom}

var phase := Phase.LOADING
var wave := 0
var sub_wave := 0
var timer_left := 0.0
var diff: Dictionary = {}
var wallets := {}                     # peer_id -> Ether (individual wallets, no trading)
var rewards := {"purple": 0, "caps": 0, "green": 0, "runes": 0}

var _loaded := {}
var _ended := false
var _uid := 0
var _hud: Label
var _banner := ""
var my_ether := 0                      # client mirror of own wallet
var workbench: Area2D
var wb_ui: WorkbenchUI


# ================================================================== setup
func _ready() -> void:
	add_to_group("match")
	diff = GameData.DIFFICULTY[Network.difficulty]
	_layout_world()
	_build_hud()
	_build_workbench()
	player_spawner.spawn_path = players_root.get_path()
	player_spawner.spawn_function = _spawn_player_fn
	enemy_spawner.spawn_path = enemies_root.get_path()
	enemy_spawner.spawn_function = _spawn_enemy_fn
	if multiplayer.is_server():
		table.destroyed.connect(func(): _finish(false))
		Network.player_left.connect(_on_player_left)
		_mark_loaded(1)
	else:
		rpc_id(1, "srv_loaded")


func _layout_world() -> void:
	table.position = KITCHEN_CENTER
	$Kitchen/SpawnLeft.position = Vector2(50, 360)       # Pantry cabinets / fridge
	$Kitchen/SpawnTop.position = Vector2(640, 50)        # Ceiling vents / sink drain
	$Kitchen/SpawnBottom.position = Vector2(640, 670)    # Floorboards / trash chute
	# TODO(yard): procedural yard – generate obstacles from a seed shared via RPC.


@rpc("any_peer", "reliable")
func srv_loaded() -> void:
	if multiplayer.is_server():
		_mark_loaded(multiplayer.get_remote_sender_id())


func _mark_loaded(id: int) -> void:
	_loaded[id] = true
	if phase == Phase.LOADING and _loaded.size() >= Network.human_count():
		_start_run()


func _spawn_player_fn(d: Dictionary) -> Node:
	var p: Player = PLAYER_SCENE.instantiate()
	p.setup(d)
	p.position = d.pos
	p.set_multiplayer_authority(maxi(1, d.peer))   # bots are owned by the server
	if multiplayer.is_server():
		p.died.connect(_on_player_died)
	return p


func _spawn_enemy_fn(d: Dictionary) -> Node:
	var e: Enemy = ENEMY_SCENE.instantiate()
	e.setup(d)
	if multiplayer.is_server():
		e.died.connect(_on_enemy_died)
	return e


func _start_run() -> void:
	var i := 0
	for id in Network.players:
		var prof: Dictionary = Network.players[id]
		player_spawner.spawn({"peer": id, "char_id": prof.char_id, "level": prof.level,
			"pos": KITCHEN_CENTER + Vector2(-90 + 90 * i, 140), "bot": prof.get("bot", false)})
		wallets[id] = 0   # TODO Emblem of Harvest: start with +25/50/100 Ether
		i += 1
	_run_match()


# ================================================================== THE LOOP (server)
func _run_match() -> void:
	await get_tree().create_timer(1.0).timeout
	for w in range(1, GameData.WAVES + 1):
		wave = w
		await _yard_phase()
		if _ended:
			return
		await _kitchen_prep_phase()
		if _ended:
			return
		await _siege_phase()
		if _ended:
			return
		if w < GameData.WAVES:
			await _feast_phase()
			if _ended:
				return
	_finish(true)


# ------------------------------------------------------------------ PHASE A: yard hunt
func _yard_phase() -> void:
	_set_phase(Phase.YARD)
	var i := 0
	for p in _all_players():
		if p.dead:
			_revive(p, 1.0)
		p.rpc("net_teleport", YARD_ENTRANCE + Vector2(30, -60 + 60 * i))
		i += 1
	var t := GameData.YARD_DURATION
	var spawn_cd := 0.0
	while t > 0.0 and not _ended:
		await get_tree().create_timer(0.25).timeout
		t -= 0.25
		spawn_cd -= 0.25
		rpc("cl_timer", t)
		if spawn_cd <= 0.0 and _count_enemies(true) < YARD_PEST_CAP:
			spawn_cd = 1.0
			var key: String = GameData.WAVE_POOLS[wave].pick_random()
			var pos := Vector2(randf_range(YARD_RECT.position.x + 120, YARD_RECT.end.x - 40),
				randf_range(YARD_RECT.position.y + 40, YARD_RECT.end.y - 40))
			var elite: bool = diff.elites and randf() < 0.15     # Hell: elite pests outdoors
			_spawn_enemy(key, pos, true, elite)


# ------------------------------------------------------------------ dinner bell + prep
func _kitchen_prep_phase() -> void:
	for e in enemies_root.get_children():
		if e.is_yard:
			e.queue_free()
	var i := 0
	for p in _all_players():
		if p.dead:                          # still in the 10s yard respawn -> revived now
			_revive(p, 1.0)
		p.rpc("net_teleport", table.global_position + Vector2(-90 + 90 * i, 120))
		i += 1
	_set_phase(Phase.KITCHEN_PREP)
	_bots_shop()
	var t := GameData.KITCHEN_PREP
	while t > 0.0 and not _ended:
		await get_tree().create_timer(0.25).timeout
		t -= 0.25
		rpc("cl_timer", t)


# ------------------------------------------------------------------ PHASE B: siege
func _siege_phase() -> void:
	_set_phase(Phase.SIEGE)
	for s in range(1, GameData.SUBWAVES + 1):
		sub_wave = s
		rpc("cl_phase", phase, wave, sub_wave)
		var vecs := _vectors_for(s)
		var count := 5 + wave * 2 + s * 2
		for n in count:
			if _ended:
				return
			var key: String = GameData.WAVE_POOLS[wave].pick_random()
			_spawn_enemy(key, _vector_pos(vecs[n % vecs.size()]), false)
			await get_tree().create_timer(0.2).timeout
		if s == GameData.SUBWAVES:                      # final sub-wave: miniboss joins the swarm
			var boss_key := "sir_roachalot" if wave <= 2 else "ratatouille"
			_spawn_enemy(boss_key, _vector_pos(vecs[0]), false)
		await _wait_until_clear()
		if _ended:
			return
		await get_tree().create_timer(2.0).timeout

	if wave == GameData.WAVES:                          # Apex Kitchen Boss
		rpc("cl_banner", "THE TRASH KING ARRIVES!")
		_spawn_enemy("trash_king", _vector_pos("top"), false)
		await _wait_until_clear()


## Hard: two directions at once, rotating each sub-wave. Hell: all three.
func _vectors_for(sub: int) -> Array:
	var all := ["left", "top", "bottom"]
	match int(diff.vectors):
		1:
			return ["left"]
		2:
			all.remove_at((wave + sub) % 3)
			return all
	return all


func _vector_pos(v: String) -> Vector2:
	return vectors[v].global_position + Vector2(randf_range(-30, 30), randf_range(-30, 30))


func _wait_until_clear() -> void:
	while not _ended and _count_enemies(false) > 0:
		await get_tree().create_timer(0.25).timeout


func spawn_adds(count: int) -> void:   # called by the Trash King
	var vecs := ["left", "top", "bottom"]
	for i in count:
		_spawn_enemy(GameData.WAVE_POOLS[5].pick_random(), _vector_pos(vecs[i % 3]), false)


# ------------------------------------------------------------------ feast
func _feast_phase() -> void:
	_set_phase(Phase.FEAST)
	_bank_wave(wave)
	var bonus: int = GameData.FEAST_BONUS_ETHER[wave - 1]
	_award_ether(bonus)
	_bots_shop()
	rpc("cl_banner", "Wave %d defended!  +%d Ether each" % [wave, bonus])
	await get_tree().create_timer(FEAST_TIME).timeout


# ================================================================== events (server)
func _on_enemy_died(e: Enemy) -> void:
	_award_ether(e.ether)                 # per-player amount, deposited to EVERY wallet
	if is_instance_valid(e.last_src) and e.last_src is Player:
		e.last_src.on_kill()              # Caffeine Syringe etc.
	if e.is_miniboss:
		rewards.runes += 2                # TODO: real per-class rune drops
		if phase == Phase.SIEGE:          # dead teammates return at 50% HP
			for p in _all_players():
				if p.dead:
					_revive(p, 0.5, table.global_position + Vector2(0, 100))
	elif e.key == "trash_king":
		rewards.runes += 5


## Back-loaded payouts, banked once per defended wave (so dying early keeps earlier waves).
func _bank_wave(w: int) -> void:
	rewards.purple += GameData.WAVE_PURPLE[w - 1]
	rewards.caps += GameData.WAVE_CAPS[w - 1]
	rewards.green += GameData.WAVE_GREEN[w - 1]


func _on_player_died(p: Player) -> void:
	match phase:
		Phase.YARD:
			_yard_respawn(p)                        # auto-revive after 10s
		Phase.SIEGE, Phase.KITCHEN_PREP:
			# No auto-revive: stay down until the wave's miniboss/boss dies.
			var alive := _all_players().filter(func(x): return not x.dead)
			if alive.is_empty():
				_finish(false)


func _yard_respawn(p: Player) -> void:
	await get_tree().create_timer(GameData.YARD_REVIVE_TIME).timeout
	if is_instance_valid(p) and p.dead and phase == Phase.YARD and not _ended:
		_revive(p, 1.0, YARD_ENTRANCE)              # "kitchen doorway" = yard entrance


func _revive(p: Player, pct: float, at: Vector2 = Vector2.INF) -> void:
	p.server_revive(pct)
	if at != Vector2.INF:
		p.rpc("net_teleport", at)


func _on_player_left(id: int) -> void:
	wallets.erase(id)
	var p := players_root.get_node_or_null(str(id))
	if p:
		p.queue_free()
	if Network.players.is_empty():
		_finish(false)


func _award_ether(amount: int) -> void:
	for id in wallets:
		wallets[id] += amount
		_sync_wallet(id)


func spend_ether(id: int, cost: int) -> bool:   # for the future Workbench / shop
	if wallets.get(id, 0) < cost:
		return false
	wallets[id] -= cost
	_sync_wallet(id)
	return true


func _finish(victory: bool) -> void:
	if _ended:
		return
	_ended = true
	if victory:
		_bank_wave(GameData.WAVES)
	_set_phase(Phase.VICTORY if victory else Phase.DEFEAT)
	var res := rewards.duplicate()
	res.green = int(res.green * diff.reward)
	res.runes = int(res.runes * diff.reward)
	res["energy_refund"] = 0 if victory else (4 if wave <= 3 else 2)
	res["wave_reached"] = wave
	# TODO: send `res` to the account/backend instead of just showing it.
	rpc("cl_result", victory, res)
	await get_tree().create_timer(8.0).timeout
	Network.return_to_lobby()


# ================================================================== helpers (server)
func _all_players() -> Array:
	return players_root.get_children()


func _count_enemies(yard: bool) -> int:
	var n := 0
	for e in enemies_root.get_children():
		if not e.dead and e.is_yard == yard:
			n += 1
	return n


func _spawn_enemy(key: String, pos: Vector2, yard: bool, elite: bool = false) -> void:
	_uid += 1
	enemy_spawner.spawn({"key": key, "wave": wave, "pos": pos, "yard": yard, "elite": elite,
		"diff": Network.difficulty, "uid": _uid})


func _set_phase(p: Phase) -> void:
	phase = p
	rpc("cl_phase", p, wave, sub_wave)


# ================================================================== client RPCs + HUD
@rpc("authority", "call_local", "reliable")
func cl_phase(p: int, w: int, s: int) -> void:
	phase = p as Phase
	wave = w
	sub_wave = s
	if p == Phase.YARD:
		_banner = "Wave %d – hunt pests for Ether!" % w
	elif p == Phase.KITCHEN_PREP:
		_banner = "DINNER BELL! Craft + take position (10s)"
	elif p == Phase.SIEGE:
		_banner = "Defend the feast!  Sub-wave %d/3" % s


@rpc("authority", "call_local", "unreliable_ordered")
func cl_timer(t: float) -> void:
	timer_left = t


@rpc("authority", "call_local", "reliable")
func cl_wallet(v: int) -> void:
	my_ether = v


@rpc("authority", "call_local", "reliable")
func cl_banner(text: String) -> void:
	_banner = text


@rpc("authority", "call_local", "reliable")
func cl_result(victory: bool, res: Dictionary) -> void:
	_banner = "%s\nWave %d | Green %d | Purple %d | Caps %d | Runes %d | Energy refund %d" % [
		"VICTORY!" if victory else "DEFEAT", res.wave_reached, res.green, res.purple, res.caps, res.runes, res.energy_refund]


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	_hud = Label.new()
	_hud.position = Vector2(12, 8)
	layer.add_child(_hud)
	add_child(layer)


func _process(_d: float) -> void:
	var me := local_player()
	var skills := ""
	var status := ""
	var items := "-"
	var prompt := ""
	if me:
		var c: Dictionary = GameData.CHARACTERS[me.char_id]
		skills = "[Q] %s   [E] %s" % [c.skill1.name, c.skill2.name]
		status = "HP %d/%d%s" % [me.hp, me.max_hp, "  (DOWN – wait for the miniboss to fall)" if me.dead else ""]
		if not me.inventory.is_empty():
			var names: Array[String] = []
			for id in me.inventory:
				names.append(Items.item_name(id))
			items = ", ".join(names)
		if phase != Phase.YARD and not me.dead and me.global_position.distance_to(workbench.global_position) <= 110.0:
			prompt = "\n[F] Open Workbench (build items)"
	_hud.text = "%s | Wave %d/%d | %s | %ds\nFood %d%% | Ether %d | %s\n%s\nItems: %s\n%s%s" % [
		GameData.DIFFICULTY[Network.difficulty].name, wave, GameData.WAVES, Phase.keys()[phase], ceili(timer_left),
		int(table.food_pct() * 100.0), my_ether, status, skills, items, _banner, prompt]


# ================================================================== WORKBENCH + ITEM BUILDING
func _build_workbench() -> void:
	workbench = get_node_or_null("Kitchen/Workbench") as Area2D
	if workbench == null:
		workbench = Area2D.new()
		workbench.name = "Workbench"
		$Kitchen.add_child(workbench)
	if workbench.position == Vector2.ZERO:
		workbench.position = KITCHEN_CENTER + Vector2(240, -170)
	workbench.draw.connect(_draw_workbench)
	workbench.queue_redraw()
	wb_ui = WorkbenchUI.new()
	add_child(wb_ui)
	wb_ui.setup(self)


func _draw_workbench() -> void:
	workbench.draw_rect(Rect2(-46, -24, 92, 48), Color("8a6d3b"))
	workbench.draw_rect(Rect2(-46, -24, 92, 10), Color("b08d57"))
	workbench.draw_circle(Vector2(-24, 6), 7.0, Color("c0392b"))      # tools
	workbench.draw_rect(Rect2(4, 0, 30, 10), Color("95a5a6"))
	workbench.draw_string(ThemeDB.fallback_font, Vector2(-44, 42), "WORKBENCH  [F]", HORIZONTAL_ALIGNMENT_LEFT, -1, 12)


func local_player() -> Player:
	return players_root.get_node_or_null(str(multiplayer.get_unique_id())) as Player


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		var me := local_player()
		if me and not me.dead and phase != Phase.YARD and phase != Phase.LOADING \
				and me.global_position.distance_to(workbench.global_position) <= 110.0:
			wb_ui.toggle()
	elif event.is_action_pressed("ui_cancel") and wb_ui.visible:
		wb_ui.hide_ui()


# ---- client -> server requests (the UI calls these)
func request_buy(item: String) -> void:
	_to_server(&"srv_buy", [item])


func request_craft(item: String) -> void:
	_to_server(&"srv_craft", [item])


func request_build(item: String) -> void:
	_to_server(&"srv_build", [item])


func _to_server(method: StringName, args: Array) -> void:
	if multiplayer.is_server():
		callv(method, args)
	else:
		callv("rpc_id", [1, method] + args)


@rpc("any_peer", "reliable")
func srv_buy(item: String) -> void:
	if multiplayer.is_server() and _item_ok(item):
		_buy(maxi(1, multiplayer.get_remote_sender_id()), item)


@rpc("any_peer", "reliable")
func srv_craft(item: String) -> void:
	if multiplayer.is_server() and _item_ok(item):
		_craft(maxi(1, multiplayer.get_remote_sender_id()), item)


@rpc("any_peer", "reliable")
func srv_build(item: String) -> void:
	if multiplayer.is_server() and _item_ok(item):
		_make_one(maxi(1, multiplayer.get_remote_sender_id()), item)


static func _item_ok(item: String) -> bool:
	return Items.ITEMS.has(item)      # never trust client strings


# ---- server-side validation
func _player(id: int) -> Player:
	return players_root.get_node_or_null(str(id)) as Player


func _can_shop(id: int) -> bool:
	if _ended or phase == Phase.YARD or phase == Phase.LOADING:
		return false
	var p := _player(id)
	if p == null or p.dead:
		return false
	return id < 0 or p.global_position.distance_to(workbench.global_position) <= 140.0   # humans must stand at the bench


func _buy(id: int, item: String) -> bool:
	if not _can_shop(id) or not Items.is_common(item):
		return false
	var p := _player(id)
	var cost := Items.cost_of(item)
	if p.inventory.size() >= Items.MAX_SLOTS or wallets.get(id, 0) < cost:
		return false
	wallets[id] -= cost
	_sync_wallet(id)
	var inv := p.inventory.duplicate()
	inv.append(item)
	p.set_inventory(inv)
	return true


func _craft(id: int, item: String) -> bool:
	if not _can_shop(id) or Items.is_common(item):
		return false
	var p := _player(id)
	var cost := Items.cost_of(item)
	if wallets.get(id, 0) < cost:
		return false
	var inv: Variant = Items.craft(p.inventory, item)
	if inv == null:
		return false
	wallets[id] -= cost
	_sync_wallet(id)
	p.set_inventory(inv)
	return true


## Acquire ONE more copy of `item`: buys missing Commons, crafts missing Rares, then crafts the item.
## Stops (returns false) when Ether or slots run out – progress made so far is kept.
func _make_one(id: int, item: String) -> bool:
	if _player(id) == null:
		return false
	if Items.is_common(item):
		return _buy(id, item)
	var parts := Items.part_counts(item)
	var ids: Array = parts.keys()
	ids.sort_custom(func(a, b): return Items.tier(a) > Items.tier(b))     # build Rare parts first
	for part in ids:
		while Items.count(_player(id).inventory, part) < parts[part]:
			if not _make_one(id, part):
				return false
	return _craft(id, item)


func _bots_shop() -> void:
	for p in _all_players():
		if not p.is_bot:
			continue
		for goal in BotBrain.build_for(p.char_id):
			if Items.count(p.inventory, goal) == 0 and not _make_one(p.peer_id, goal):
				break


func _sync_wallet(id: int) -> void:
	if id == multiplayer.get_unique_id():
		cl_wallet(wallets[id])                     # host's own wallet: no network hop
	elif id > 0:
		rpc_id(id, "cl_wallet", wallets[id])
