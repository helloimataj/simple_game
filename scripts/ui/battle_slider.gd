class_name BattleSlider
extends Control
## Draws the battle slider: the attacker's zone, the defender's zone, the bell
## curve the roll is drawn from, and the last roll.

var _attack := 0.0
var _defense := 0.0
var _attack_color := Color.BLUE
var _defense_color := Color.RED
var _roll := {}


func _init() -> void:
	custom_minimum_size = Vector2(0, 92)


func show_state(attack: float, defense: float, attack_color: Color, defense_color: Color,
		last_roll: Dictionary) -> void:
	_attack = attack
	_defense = defense
	_attack_color = attack_color
	_defense_color = defense_color
	_roll = last_roll
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var font_size := 13
	var left := 10.0
	var width := size.x - 20.0
	var bar_top := 44.0
	var bar_height := 22.0
	var total := _attack + _defense
	if total <= 0.0 or width <= 0.0:
		return
	# If a roll is shown, draw the slider as it was for that roll.
	var line := _attack
	if not _roll.is_empty():
		total = _roll["total"]
		line = _roll["line"]
	var line_x := left + width * line / total

	draw_rect(Rect2(left, bar_top, line_x - left, bar_height), _attack_color.darkened(0.15))
	draw_rect(Rect2(line_x, bar_top, left + width - line_x, bar_height), _defense_color.darkened(0.15))

	# Bell curve: centred on the middle, standard deviation SPREAD x total.
	var points := PackedVector2Array()
	var steps := 80
	for i in steps + 1:
		var x := float(i) / steps
		var z := (x - 0.5) / Battle.SPREAD
		points.append(Vector2(left + width * x, bar_top - 2.0 - 34.0 * exp(-0.5 * z * z)))
	draw_polyline(points, Color(1, 1, 1, 0.7), 1.5, true)
	draw_line(Vector2(left + width * 0.5, bar_top - 36.0), Vector2(left + width * 0.5, bar_top + bar_height),
		Color(1, 1, 1, 0.25), 1.0)

	# Dividing line.
	draw_line(Vector2(line_x, bar_top - 6.0), Vector2(line_x, bar_top + bar_height + 6.0), Color.WHITE, 2.0)

	# End labels are skipped when the line label would sit on top of them.
	var label_y := bar_top + bar_height + 18.0
	if line_x - left > 100.0:
		draw_string(font, Vector2(left, label_y), "0", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	if left + width - line_x > 130.0:
		draw_string(font, Vector2(left + width - 80.0, label_y), "%.1f" % total,
			HORIZONTAL_ALIGNMENT_RIGHT, 80.0, font_size)
	var line_label_x := clampf(line_x - 80.0, left, left + width - 160.0)
	draw_string(font, Vector2(line_label_x, label_y), "line %.1f of %.1f" % [line, total],
		HORIZONTAL_ALIGNMENT_CENTER, 160.0, font_size)

	if not _roll.is_empty():
		var roll_x: float = left + width * _roll["roll"] / total
		draw_line(Vector2(roll_x, bar_top - 4.0), Vector2(roll_x, bar_top + bar_height + 4.0), Color("ffd23f"), 3.0)
		draw_colored_polygon(PackedVector2Array([
			Vector2(roll_x - 6.0, bar_top - 12.0), Vector2(roll_x + 6.0, bar_top - 12.0),
			Vector2(roll_x, bar_top - 3.0)]), Color("ffd23f"))
		# Damage span between the roll and the line.
		draw_rect(Rect2(minf(roll_x, line_x), bar_top + bar_height * 0.35, absf(roll_x - line_x), bar_height * 0.3),
			Color(1, 0.82, 0.25, 0.8))
		var roll_label_x := clampf(roll_x - 110.0, left, left + width - 220.0)
		draw_string(font, Vector2(roll_label_x, 12.0), "roll %.1f: %d damage" % [_roll["roll"], _roll["damage"]],
			HORIZONTAL_ALIGNMENT_CENTER, 220.0, font_size, Color("ffd23f"))
