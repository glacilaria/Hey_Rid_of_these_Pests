class_name SkillCooldownHUD
extends Control
## Two circles at the bottom-centre of the screen, one per skill ([Q] and [E]).
## Each circle fills clockwise from the top as the cooldown runs; when it is full the
## skill is ready (bright ring + key letter). While cooling down it shows the seconds left.

const RADIUS := 34.0
const SPACING := 150.0
const BOTTOM_MARGIN := 62.0
const KEYS := {1: "Q", 2: "E"}
const COL_BG := Color(0.08, 0.08, 0.10, 0.75)
const COL_FILL := Color(0.30, 0.65, 1.00, 0.85)
const COL_READY := Color(0.35, 0.90, 0.45, 1.0)

var mm: MatchManager


func setup(match_manager: MatchManager) -> void:
	mm = match_manager
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	var me := mm.local_player() if mm != null else null
	if me == null:
		return
	var def: Dictionary = GameData.CHARACTERS[me.char_id]
	var font := ThemeDB.fallback_font
	var mid := Vector2(size.x * 0.5, size.y - BOTTOM_MARGIN)
	for slot in [1, 2]:
		var c := mid + Vector2((slot - 1.5) * SPACING, 0.0)
		var fill: float = me.cd_fill(slot)
		var ready: bool = me.cd[slot] <= 0.0
		draw_circle(c, RADIUS, COL_BG)
		if ready:
			draw_circle(c, RADIUS - 3.0, Color(COL_READY, 0.35))
		elif fill > 0.0:
			draw_colored_polygon(_pie(c, RADIUS - 3.0, fill), COL_FILL)
		draw_arc(c, RADIUS, 0.0, TAU, 48, COL_READY if ready else Color(1, 1, 1, 0.55), 3.0, true)
		var label: String = KEYS[slot] if ready else "%.1f" % float(me.cd[slot])
		draw_string(font, c + Vector2(-RADIUS, 8.0), label, HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2.0, 22, Color.WHITE)
		var sname: String = def["skill%d" % slot].name
		draw_string(font, c + Vector2(-75.0, RADIUS + 18.0), sname, HORIZONTAL_ALIGNMENT_CENTER, 150.0, 12, Color(1, 1, 1, 0.85))
		if not ready:
			draw_string(font, c + Vector2(-RADIUS, -RADIUS - 6.0), KEYS[slot], HORIZONTAL_ALIGNMENT_CENTER, RADIUS * 2.0, 13, Color(1, 1, 1, 0.7))


## Filled wedge starting at 12 o'clock going clockwise; fraction 0..1.
static func _pie(center: Vector2, r: float, fraction: float) -> PackedVector2Array:
	var pts := PackedVector2Array([center])
	var steps := maxi(2, int(48.0 * fraction))
	for i in steps + 1:
		var a := -PI * 0.5 + TAU * fraction * float(i) / float(steps)
		pts.append(center + Vector2(cos(a), sin(a)) * r)
	return pts
