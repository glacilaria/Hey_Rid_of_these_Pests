extends Node2D
## INTERACTIVE LOBBY – a small top-down room you walk around in (WASD), press F near things:
##   Door (right wall)    -> outside: lobby management (quick match + 2 bots, private room, start)
##   Character Shelf      -> pick your defender
##   Vending Machine      -> gacha (placeholder panel)
##   Contract Board       -> daily/weekly Exterminator contracts (placeholder panel)
##   Emblem Drawer        -> emblem page (placeholder panel)
## The rug shows your party (humans + bots). Everything is drawn in code – no art or child nodes needed.

const SPEED := 230.0

var room := Rect2()
var hero := Vector2.ZERO
var spots := {}
var near_id := ""
var panel_open := ""

var ui := CanvasLayer.new()
var panel := PanelContainer.new()
var body := VBoxContainer.new()

# matchmaking panel refs
var _mm_status: Label
var _mm_roster: Label
var _mm_count: Label
var _mm_code: LineEdit
var _mm_host_row: HBoxContainer
# character panel refs
var _char_info: Label


func _ready() -> void:
	var vs := get_viewport_rect().size
	room = Rect2(32, 32, vs.x - 64, vs.y - 64)
	hero = room.get_center() + Vector2(0, 150)
	var cy := room.get_center().y
	spots = {
		"door":    {"pos": Vector2(room.end.x - 14, cy), "r": 70.0, "text": "Go outside – lobby management"},
		"shelf":   {"pos": room.position + Vector2(170, 60), "r": 60.0, "text": "Character Shelf"},
		"gacha":   {"pos": Vector2(room.get_center().x, room.position.y + 60), "r": 60.0, "text": "Gacha Vending Machine"},
		"board":   {"pos": Vector2(room.end.x - 230, room.position.y + 55), "r": 60.0, "text": "Contract Board"},
		"drawer":  {"pos": Vector2(room.position.x + 80, room.end.y - 70), "r": 60.0, "text": "Emblem Drawer"},
	}
	ui.layer = 10
	add_child(ui)
	panel.visible = false
	panel.custom_minimum_size = Vector2(520, 0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	ui.add_child(panel)
	panel.add_child(body)
	Network.status.connect(_on_status)
	Network.roster_changed.connect(_on_roster)
	Network.countdown.connect(_on_countdown)


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if panel_open == "":
		var dir := Input.get_vector("move_left", "move_right", "move_up", "move_down")
		hero += dir * SPEED * delta
		hero = hero.clamp(room.position + Vector2(24, 24), room.end - Vector2(24, 24))
	near_id = ""
	var best := INF
	for id in spots:
		var d := hero.distance_to(spots[id].pos)
		if d < spots[id].r + 30.0 and d < best:
			best = d
			near_id = id
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and panel_open == "" and near_id != "":
		_open(near_id)
	elif event.is_action_pressed("ui_cancel") and panel_open != "":
		_close()


# ------------------------------------------------------------------ drawing
func _draw() -> void:
	var f := ThemeDB.fallback_font
	draw_rect(room, Color("d9c7a3"))                                       # floor
	for i in range(0, int(room.size.x), 64):                               # floorboards
		draw_line(room.position + Vector2(i, 0), room.position + Vector2(i, room.size.y), Color(0, 0, 0, 0.05), 1.0)
	draw_rect(room, Color("5b3a29"), false, 10.0)                          # walls

	# rug + party slots
	var rc := room.get_center() + Vector2(-40, 70)
	draw_circle(rc, 190.0, Color("a64b4b", 0.55))
	draw_arc(rc, 190.0, 0.0, TAU, 64, Color("7d2f2f"), 4.0)
	draw_string(f, rc + Vector2(-60, -150), "YOUR PARTY", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("3b1d1d"))
	var ids: Array = Network.players.keys()
	for i in GameData.MAX_PLAYERS:
		var p := rc + Vector2(-110 + 110 * i, 0)
		if i < ids.size():
			var pr: Dictionary = Network.players[ids[i]]
			var cdef: Dictionary = GameData.CHARACTERS[pr.char_id]
			draw_circle(p, 22.0, cdef.color)
			draw_arc(p, 22.0, 0.0, TAU, 24, Color.BLACK, 2.0)
			draw_string(f, p + Vector2(-48, 42), pr.name, HORIZONTAL_ALIGNMENT_CENTER, 96, 12, Color.BLACK)
			draw_string(f, p + Vector2(-48, 56), cdef.name, HORIZONTAL_ALIGNMENT_CENTER, 96, 11, Color("333333"))
		else:
			draw_arc(p, 22.0, 0.0, TAU, 24, Color(0, 0, 0, 0.35), 2.0)
			draw_string(f, p + Vector2(-48, 6), "empty", HORIZONTAL_ALIGNMENT_CENTER, 96, 12, Color(0, 0, 0, 0.4))

	# character shelf (top-left)
	var s: Vector2 = spots.shelf.pos
	draw_rect(Rect2(s + Vector2(-110, -30), Vector2(220, 70)), Color("7b4a2a"))
	var k := 0
	for id in GameData.CHARACTERS:
		draw_circle(s + Vector2(-90 + 20 * k, 4), 8.0, GameData.CHARACTERS[id].color)
		k += 1
	_label(f, s + Vector2(-100, 60), "CHARACTER SHELF")

	# vending machine (top-middle)
	var g: Vector2 = spots.gacha.pos
	draw_rect(Rect2(g + Vector2(-34, -44), Vector2(68, 92)), Color("c0392b"))
	draw_rect(Rect2(g + Vector2(-24, -34), Vector2(48, 44)), Color("fdebd0"))
	draw_circle(g + Vector2(0, 30), 7.0, Color("f4d03f"))
	_label(f, g + Vector2(-60, 66), "GACHA VENDING MACHINE")

	# contract board (top-right)
	var b: Vector2 = spots.board.pos
	draw_rect(Rect2(b + Vector2(-70, -38), Vector2(140, 76)), Color("b07d4f"))
	draw_rect(Rect2(b + Vector2(-60, -28), Vector2(32, 26)), Color("fffbe6"))
	draw_rect(Rect2(b + Vector2(-16, -28), Vector2(32, 26)), Color("fffbe6"))
	draw_rect(Rect2(b + Vector2(28, -28), Vector2(32, 26)), Color("fffbe6"))
	_label(f, b + Vector2(-62, 56), "CONTRACT BOARD")

	# emblem drawer (bottom-left)
	var d: Vector2 = spots.drawer.pos
	draw_rect(Rect2(d + Vector2(-60, -30), Vector2(120, 64)), Color("8e6e53"))
	for j in 3:
		draw_rect(Rect2(d + Vector2(-52, -24 + 20 * j), Vector2(104, 14)), Color("a58468"))
	_label(f, d + Vector2(-56, 52), "EMBLEM DRAWER")

	# door to the outside (right wall)
	var dr: Vector2 = spots.door.pos
	draw_rect(Rect2(dr + Vector2(-10, -64), Vector2(34, 128)), Color("3e8e41", 0.55))   # light from outside
	draw_rect(Rect2(dr + Vector2(-24, -60), Vector2(26, 120)), Color("8a5a2b"))
	draw_circle(dr + Vector2(-8, 4), 4.0, Color("f4d03f"))
	var sign_text := "OUTSIDE ▶ %s" % Network.room_code if Network.in_room() else "OUTSIDE ▶ LOBBY"
	draw_string(f, dr + Vector2(-190, -76), sign_text, HORIZONTAL_ALIGNMENT_RIGHT, 180, 15, Color("2b4d2c"))

	# hero
	var me: Dictionary = GameData.CHARACTERS[Network.local_profile.char_id]
	draw_circle(hero, 14.0, me.color)
	draw_arc(hero, 14.0, 0.0, TAU, 24, Color.WHITE, 2.0)
	draw_string(f, hero + Vector2(-40, -22), "You", HORIZONTAL_ALIGNMENT_CENTER, 80, 12, Color.BLACK)

	# prompt + help
	if near_id != "" and panel_open == "":
		var sp: Dictionary = spots[near_id]
		var tp: Vector2 = hero + Vector2(-110, -42)
		draw_rect(Rect2(tp + Vector2(-6, -16), Vector2(236, 24)), Color(0, 0, 0, 0.65))
		draw_string(f, tp, "[F] %s" % sp.text, HORIZONTAL_ALIGNMENT_LEFT, 230, 14, Color.WHITE)
	draw_string(f, room.position + Vector2(14, room.size.y - 12), "WASD move   ·   F interact   ·   Esc close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("3b2a1d"))


func _label(f: Font, pos: Vector2, text: String) -> void:
	draw_string(f, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("3b2a1d"))


# ------------------------------------------------------------------ panels
func _open(id: String) -> void:
	panel_open = id
	for c in body.get_children():
		c.queue_free()
	match id:
		"door":
			_build_matchmaking()
		"shelf":
			_build_characters()
		"gacha":
			_build_info("Gacha Vending Machine", [
				"25 Bottle Caps = 1 pull   ·   250 Bottle Caps = 10 pulls",
				"Rolls characters and emblems.",
				"(Placeholder – account currencies and pull logic are not built yet.)"])
		"board":
			_build_info("Exterminator Contract Board", [
				"• Defeat Wave 5 with over 80% Food Integrity   →  5,000–15,000 Green Ether",
				"• Eliminate 500 Sprinter Roaches in Online Co-op",
				"(Placeholder – quest tracking is not built yet.)"])
		"drawer":
			_build_info("Emblem Drawer", [
				"Configure your 10-slot Emblem Page, upgrade emblems (+10) and view set bonuses (3/6/10).",
				"(Placeholder – emblem inventory is not built yet.)"])
	panel.visible = true


func _close() -> void:
	panel_open = ""
	panel.visible = false


func _title(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 20)
	body.add_child(l)
	body.add_child(HSeparator.new())


func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(cb)
	body.add_child(b)
	return b


func _build_info(title: String, lines: Array) -> void:
	_title(title)
	for t in lines:
		var l := Label.new()
		l.text = t
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_child(l)
	_btn("Close", _close)


# ---- door: lobby management / matchmaking
func _build_matchmaking() -> void:
	_title("Outside – Lobby Management")
	_mm_status = Label.new()
	_mm_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_mm_status)
	_btn("Quick Match  (fills the party with 2 bots)", _on_quick)
	_btn("Create Private Room", _on_create)
	var row := HBoxContainer.new()
	_mm_code = LineEdit.new()
	_mm_code.placeholder_text = "Room code (e.g. ABCD)"
	_mm_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_mm_code)
	var join := Button.new()
	join.text = "Join Room"
	join.pressed.connect(_on_join)
	row.add_child(join)
	body.add_child(row)

	var drow := HBoxContainer.new()
	var dl := Label.new()
	dl.text = "Difficulty: "
	drow.add_child(dl)
	var diff := OptionButton.new()
	for d in GameData.DIFFICULTY:
		diff.add_item(GameData.DIFFICULTY[d].name, d)
	diff.selected = Network.difficulty
	diff.item_selected.connect(_on_diff)
	drow.add_child(diff)
	body.add_child(drow)

	body.add_child(HSeparator.new())
	_mm_roster = Label.new()
	body.add_child(_mm_roster)
	_mm_count = Label.new()
	body.add_child(_mm_count)

	_mm_host_row = HBoxContainer.new()
	for spec in [["Start Match", _on_start], ["+ Bot", _on_add_bot], ["Remove bots", _on_remove_bots]]:
		var hb := Button.new()
		hb.text = spec[0]
		hb.pressed.connect(spec[1])
		_mm_host_row.add_child(hb)
	body.add_child(_mm_host_row)
	_btn("Leave Room", _on_leave)
	_btn("Back inside", _close)
	_refresh_mm()


func _refresh_mm() -> void:
	if panel_open != "door" or _mm_roster == null or not is_instance_valid(_mm_roster):
		return
	var lines: Array[String] = []
	for id in Network.players:
		var p: Dictionary = Network.players[id]
		lines.append("  %s – %s%s" % [p.name, GameData.CHARACTERS[p.char_id].name, "  (host)" if id == 1 else ""])
	_mm_roster.text = "Room %s  (%d/%d)\n%s" % [Network.room_code, Network.players.size(), GameData.MAX_PLAYERS,
		"\n".join(lines)] if Network.in_room() else "Not in a room."
	_mm_host_row.visible = Network.is_host()


func _on_status(t: String) -> void:
	if panel_open == "door" and _mm_status and is_instance_valid(_mm_status):
		_mm_status.text = t


func _on_roster() -> void:
	_refresh_mm()


func _on_countdown(t: float) -> void:
	if panel_open == "door" and _mm_count and is_instance_valid(_mm_count):
		_mm_count.text = "Quick match starting in %d..." % ceili(t)


func _on_quick() -> void:
	Network.quick_match()


func _on_create() -> void:
	Network.host_room()


func _on_join() -> void:
	Network.join_by_code(_mm_code.text)


func _on_diff(i: int) -> void:
	Network.difficulty = i


func _on_start() -> void:
	Network.start_match(Network.difficulty)


func _on_add_bot() -> void:
	Network.add_bot()


func _on_remove_bots() -> void:
	Network.remove_bots()


func _on_leave() -> void:
	Network.leave()
	_mm_count.text = ""
	_refresh_mm()


# ---- shelf: character selection
func _build_characters() -> void:
	_title("Character Shelf")
	var grid := GridContainer.new()
	grid.columns = 2
	body.add_child(grid)
	for id in GameData.CHARACTERS:
		var c: Dictionary = GameData.CHARACTERS[id]
		var b := Button.new()
		b.text = "%s – %s" % [c.name, c.role]
		b.pressed.connect(_pick_char.bind(id))
		grid.add_child(b)
	_char_info = Label.new()
	_char_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(_char_info)
	_show_char(Network.local_profile.char_id)
	_btn("Close", _close)


func _pick_char(id: String) -> void:
	Network.local_profile["char_id"] = id
	Network.update_profile()
	_show_char(id)


func _show_char(id: String) -> void:
	var c: Dictionary = GameData.CHARACTERS[id]
	_char_info.text = "%s  (%s)\nHP %d · ATK %d · ASPD %.2f · SPD %d\n[Q] %s – CD %ds\n[E] %s – CD %ds\nRole in bot teams: %s" % [
		c.name, c.role, c.hp, c.atk, c.aspd, c.spd, c.skill1.name, c.skill1.cd, c.skill2.name, c.skill2.cd, BotBrain.role(id)]
