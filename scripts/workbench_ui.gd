class_name WorkbenchUI
extends CanvasLayer
## Item-building screen opened at the kitchen Workbench (press F next to it).
## Columns:  SHOP (Commons, 60 Ether)  |  RECIPES (Rare 80 / Epic 220)  |  YOUR ITEMS (6 slots).
## Every button only sends a REQUEST to the server (MatchManager.request_*);
## the server validates Ether, slots and distance, then updates the player's inventory.

var mm: MatchManager
var _root: PanelContainer
var _title: Label
var _shop_box: VBoxContainer
var _recipe_box: VBoxContainer
var _inv_box: VBoxContainer
var _sig := ""


func setup(match_manager: MatchManager) -> void:
	mm = match_manager
	layer = 20
	visible = false
	_build()


func _build() -> void:
	_root = PanelContainer.new()
	_root.custom_minimum_size = Vector2(1060, 560)
	_root.set_anchors_preset(Control.PRESET_CENTER)
	_root.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_root.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(_root)

	var outer := VBoxContainer.new()
	_root.add_child(outer)

	var head := HBoxContainer.new()
	outer.add_child(head)
	_title = Label.new()
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_title)
	var close := Button.new()
	close.text = "Close [Esc]"
	close.pressed.connect(hide_ui)
	head.add_child(close)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 14)
	outer.add_child(cols)

	_shop_box = _column(cols, "SHOP  (Common – 60 Ether)", 260)
	_recipe_box = _column(cols, "RECIPES  (Rare 80 · Epic 220 Ether)", 560)
	_inv_box = _column(cols, "YOUR ITEMS", 210)


func _column(parent: Control, heading: String, width: float) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = width
	var l := Label.new()
	l.text = heading
	v.add_child(l)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(sc)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(content)
	parent.add_child(v)
	return content


func toggle() -> void:
	if visible:
		hide_ui()
	else:
		visible = true
		_sig = ""


func hide_ui() -> void:
	visible = false


func _process(_d: float) -> void:
	if not visible:
		return
	if mm.phase in [MatchManager.Phase.LOADING, MatchManager.Phase.VICTORY, MatchManager.Phase.DEFEAT]:
		hide_ui()
		return
	var me := mm.local_player()
	if me == null or me.dead or me.global_position.distance_to(mm.workbench.global_position) > 160.0:
		hide_ui()
		return
	var sig := "%s|%d|%s" % [str(me.inventory), mm.my_ether, mm.phase]
	if sig != _sig:
		_sig = sig
		_rebuild(me)


func _rebuild(me: Player) -> void:
	for box in [_shop_box, _recipe_box, _inv_box]:
		for c in box.get_children():
			c.queue_free()
	_title.text = "WORKBENCH     Ether: %d     Slots: %d/%d" % [mm.my_ether, me.inventory.size(), Items.MAX_SLOTS]

	# ---- shop
	for id in Items.COMMON_IDS:
		var b := Button.new()
		b.text = "%s  %s  –  %d" % [Items.item_name(id), Items.ITEMS[id].short, Items.cost_of(id)]
		b.disabled = mm.my_ether < Items.cost_of(id) or me.inventory.size() >= Items.MAX_SLOTS
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(mm.request_buy.bind(id))
		_shop_box.add_child(b)

	# ---- recipes
	for id in Items.RARE_IDS + Items.EPIC_IDS:
		_recipe_box.add_child(_recipe_row(id, me))

	# ---- inventory
	for i in Items.MAX_SLOTS:
		var l := Label.new()
		if i < me.inventory.size():
			var id: String = me.inventory[i]
			l.text = "%d. %s\n    %s" % [i + 1, Items.item_name(id), Items.ITEMS[id].short]
			l.tooltip_text = Items.ITEMS[id].get("passive", "")
		else:
			l.text = "%d. (empty)" % [i + 1]
			l.modulate = Color(1, 1, 1, 0.4)
		_inv_box.add_child(l)


func _recipe_row(id: String, me: Player) -> Control:
	var it: Dictionary = Items.ITEMS[id]
	var cost := Items.cost_of(id)
	var tag := "EPIC" if it.tier == 3 else "RARE"
	var row := VBoxContainer.new()

	var info := Label.new()
	info.text = "[%s] %s – %s\n   %s\n   Parts: %s" % [tag, it.name, it.short, it.passive, Items.recipe_text(id)]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size.x = 520
	if it.tier == 3:
		info.modulate = Color(1.0, 0.85, 0.4)
	row.add_child(info)

	var btns := HBoxContainer.new()
	row.add_child(btns)
	var craft := Button.new()
	craft.text = "Craft (%d)" % cost
	craft.disabled = not Items.can_craft(me.inventory, id) or mm.my_ether < cost
	craft.pressed.connect(mm.request_craft.bind(id))
	btns.add_child(craft)
	var build := Button.new()          # buys every missing part, then crafts – as far as Ether allows
	build.text = "Auto-build path"
	build.pressed.connect(mm.request_build.bind(id))
	btns.add_child(build)
	row.add_child(HSeparator.new())
	return row
