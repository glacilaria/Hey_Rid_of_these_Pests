class_name DiningTable
extends Area2D
## The thing being defended. Attach to Kitchen/DiningTable in match.tscn.
## Food Integrity hits 0 -> run is lost. Standing within 3 tiles heals 3% max HP/s.

signal food_changed(food: float, max_food: float)
signal destroyed

var radius := 60.0
var food := GameData.TABLE_MAX_FOOD
var invulnerable := false    # Mega Bubble Dome
var damage_reduction := 0.0  # TODO: Clank "Head Chef's Guard" passive
var aura_mult := 1.0         # TODO: Whisker/Emblem of Sanctuary boosts


func _ready() -> void:
	add_to_group("table")


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		for p in Combat.players():
			if p.global_position.distance_to(global_position) <= GameData.TABLE_AURA_RADIUS + radius:
				p.heal(p.max_hp * GameData.TABLE_AURA_REGEN * aura_mult * delta)
	queue_redraw()


func take_damage(amount: float) -> void:
	if not multiplayer.is_server() or invulnerable or food <= 0.0:
		return
	food = maxf(0.0, food - amount * (1.0 - damage_reduction))
	rpc("net_food", food)
	if food <= 0.0:
		destroyed.emit()


@rpc("authority", "call_local", "unreliable_ordered")
func net_food(f: float) -> void:
	food = f
	food_changed.emit(food, GameData.TABLE_MAX_FOOD)


func food_pct() -> float:
	return food / GameData.TABLE_MAX_FOOD


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + GameData.TABLE_AURA_RADIUS, Color(0.3, 1.0, 0.4, 0.06))
	draw_rect(Rect2(-radius, -radius * 0.6, radius * 2.0, radius * 1.2), Color("7b4a2a"))
	draw_rect(Rect2(-radius, -radius * 0.6 - 14, radius * 2.0, 8), Color(0, 0, 0, 0.6))
	draw_rect(Rect2(-radius, -radius * 0.6 - 14, radius * 2.0 * food_pct(), 8), Color.ORANGE)
	if invulnerable:
		draw_arc(Vector2.ZERO, radius + 10.0, 0.0, TAU, 40, Color(0.5, 0.9, 1.0), 3.0)
