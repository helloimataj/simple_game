class_name BattlePanel
extends Control
## Modal screen that walks two players through a Battle.
##
## One primary button drives the sequence. Unit rows are buttons: during
## commit and retreat they toggle a unit in or out; while damage is being
## assigned, clicking a unit puts the damage on it.
##
## Retreat choices are made one side at a time and hidden before the other
## side chooses, then revealed together.

signal closed

enum Stage { COMMIT_ATTACKER, COMMIT_DEFENDER, ROLL, ASSIGN, RETREAT_ATTACKER, RETREAT_DEFENDER, FINISHED }

var battle: Battle
var stage := Stage.COMMIT_ATTACKER

var _picked := {}                     # Unit -> true, for the side choosing now
var _attacker_choice: Array = []      # locked-in attacker commit / retreat
var _title: Label
var _columns: Array[VBoxContainer] = []
var _headers: Array[Label] = []
var _slider: BattleSlider
var _status: Label
var _log: RichTextLabel
var _primary: Button
var _secondary: Button
var _shown_power: Array[float] = [0.0, 0.0]  # per side, with the current ticks


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	visible = false

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(820, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.1, 0.13, 0.97)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)

	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 16)
	box.add_child(sides)
	for side in 2:
		var column := VBoxContainer.new()
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var header := Label.new()
		header.add_theme_font_size_override("font_size", 17)
		column.add_child(header)
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size = Vector2(0, 170)
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var list := VBoxContainer.new()
		list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(list)
		column.add_child(scroll)
		sides.add_child(column)
		_headers.append(header)
		_columns.append(list)

	_slider = BattleSlider.new()
	box.add_child(_slider)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color("ffd23f"))
	box.add_child(_status)

	_log = RichTextLabel.new()
	_log.custom_minimum_size = Vector2(0, 120)
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 14)
	box.add_child(_log)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	_secondary = Button.new()
	_secondary.pressed.connect(_on_secondary)
	buttons.add_child(_secondary)
	_primary = Button.new()
	_primary.add_theme_font_size_override("font_size", 18)
	_primary.custom_minimum_size = Vector2(220, 0)
	_primary.pressed.connect(_on_primary)
	buttons.add_child(_primary)


func open(new_battle: Battle) -> void:
	battle = new_battle
	stage = Stage.COMMIT_ATTACKER
	_pick_all(Battle.ATTACKER)
	visible = true
	_refresh()


# --- Driving the battle ------------------------------------------------------------

func _on_primary() -> void:
	match stage:
		Stage.COMMIT_ATTACKER:
			if _picked.is_empty():
				return
			_attacker_choice = _picked.keys()
			stage = Stage.COMMIT_DEFENDER
			_pick_all(Battle.DEFENDER)
		Stage.COMMIT_DEFENDER:
			battle.commit(_attacker_choice, _picked.keys())
			_picked.clear()
			_sync_stage()
		Stage.ROLL:
			battle.roll_round()
			_sync_stage()
		Stage.ASSIGN:
			battle.auto_assign()
			_sync_stage()
		Stage.RETREAT_ATTACKER:
			_attacker_choice = _picked.keys()
			_picked.clear()
			stage = Stage.RETREAT_DEFENDER
		Stage.RETREAT_DEFENDER:
			battle.submit_retreat(_attacker_choice, _picked.keys())
			_picked.clear()
			_sync_stage()
		Stage.FINISHED:
			visible = false
			closed.emit()
			return
	_refresh()


## Secondary button: cancel before anything is committed.
func _on_secondary() -> void:
	if stage == Stage.COMMIT_ATTACKER:
		visible = false
		closed.emit()


func _on_unit_pressed(unit: Unit, side: int) -> void:
	if stage == Stage.ASSIGN:
		battle.assign(unit)
		_sync_stage()
	elif _choosing_side() == side:
		if _picked.has(unit):
			_picked.erase(unit)
		else:
			_picked[unit] = true
	_refresh()


## Matches the panel's stage to the battle's phase after an engine call.
func _sync_stage() -> void:
	match battle.phase:
		Battle.Phase.ROLL:
			stage = Stage.ROLL
		Battle.Phase.ASSIGN:
			stage = Stage.ASSIGN
		Battle.Phase.RETREAT:
			stage = Stage.RETREAT_ATTACKER
		Battle.Phase.FINISHED:
			stage = Stage.FINISHED


func _pick_all(side: int) -> void:
	_picked.clear()
	for unit in battle.candidates(side):
		_picked[unit] = true


## The side currently toggling units, or -1.
func _choosing_side() -> int:
	match stage:
		Stage.COMMIT_ATTACKER, Stage.RETREAT_ATTACKER:
			return Battle.ATTACKER
		Stage.COMMIT_DEFENDER, Stage.RETREAT_DEFENDER:
			return Battle.DEFENDER
	return -1


# --- Display -----------------------------------------------------------------------

func _refresh() -> void:
	var planet := battle.planet
	_title.text = "Battle for %s  (tile %d%s)" % [
		Biomes.display_name(planet.biomes[battle.tile]), battle.tile,
		", city" if battle.game.is_city(battle.tile) else ""]

	var committing := stage == Stage.COMMIT_ATTACKER or stage == Stage.COMMIT_DEFENDER
	var pool := battle.damage_pool() if stage == Stage.ASSIGN else []
	for side in 2:
		var units: Array = battle.committed[side]
		if committing:
			units = battle.candidates(side) if side == _choosing_side() or stage == Stage.COMMIT_ATTACKER \
				else _attacker_choice
		# Fills the list and works out the side's power with the units ticked.
		_fill_column(side, units, pool)
		var role := "Attacker" if side == Battle.ATTACKER else "Defender x%.2f" % battle.defender_multiplier()
		_headers[side].text = "%s  (%s)   Power %.1f" % [battle.side_name(side), role, _shown_power[side]]
		_headers[side].add_theme_color_override("font_color", _side_color(side).lightened(0.3))

	_slider.show_state(_shown_power[Battle.ATTACKER], _shown_power[Battle.DEFENDER], _side_color(Battle.ATTACKER), _side_color(Battle.DEFENDER),
		battle.last_roll if stage != Stage.COMMIT_ATTACKER and stage != Stage.COMMIT_DEFENDER else {})

	_secondary.visible = stage == Stage.COMMIT_ATTACKER
	_secondary.text = "Cancel attack"
	_primary.disabled = false
	match stage:
		Stage.COMMIT_ATTACKER:
			_status.text = "%s: choose the units to commit to the attack." % battle.side_name(Battle.ATTACKER)
			_primary.text = "Commit attackers"
			_primary.disabled = _picked.is_empty()
		Stage.COMMIT_DEFENDER:
			_status.text = "%s: choose the units to defend. Units left out retreat to an adjacent safe tile, or are lost if there is none." % battle.side_name(Battle.DEFENDER)
			_primary.text = "Commit defenders"
		Stage.ROLL:
			_status.text = "Round %d. The side whose zone the roll lands in deals damage equal to the distance from the line." % (battle.round_number + 1)
			_primary.text = "Roll"
		Stage.ASSIGN:
			var damage := battle.current_damage()
			_status.text = "%s: assign %d damage. Click a unit to take it (it absorbs as much as it can), or auto-assign to lose the cheapest first." % [
				battle.side_name(damage["side"]), damage["amount"]]
			_primary.text = "Auto-assign"
		Stage.RETREAT_ATTACKER:
			_status.text = "%s: secretly choose units to pull out (%s, look away). Retreating units take a pursuit hit of %d%% of the enemy's power." % [
				battle.side_name(Battle.ATTACKER), battle.side_name(Battle.DEFENDER), roundi(Battle.PURSUIT_SHARE * 100)]
			_primary.text = "Lock in"
		Stage.RETREAT_DEFENDER:
			_status.text = "%s: secretly choose units to pull out. %s's choice is hidden until you reveal." % [
				battle.side_name(Battle.DEFENDER), battle.side_name(Battle.ATTACKER)]
			_primary.text = "Reveal retreats"
		Stage.FINISHED:
			_status.text = "%s wins." % battle.side_name(battle.winner)
			_primary.text = "Close"

	_log.text = "\n".join(battle.events)


func _fill_column(side: int, units: Array, pool: Array) -> void:
	var list := _columns[side]
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	var choosing := _choosing_side() == side
	var committing := stage == Stage.COMMIT_ATTACKER or stage == Stage.COMMIT_DEFENDER
	var total := 0.0
	for unit: Unit in units:
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var notes: Array[String] = []
		if battle.is_remote(unit):
			notes.append("support")
		if not battle.is_supplied(unit):
			notes.append("out of supply")
		var marker := ""
		if choosing:
			var ticked := _picked.has(unit)
			marker = ("[x] " if ticked else "[  ] ") if committing else ("[retreat] " if ticked else "[stay] ")
			if ticked == committing:
				total += battle.unit_power(unit, side)
		else:
			total += battle.unit_power(unit, side)
		button.text = "%s%s   HP %d/%d   power %.1f%s" % [
			marker, unit.display_name(), unit.hit_points, unit.data()["power"],
			battle.unit_power(unit, side), ("   (%s)" % ", ".join(notes)) if not notes.is_empty() else ""]
		button.disabled = not (choosing or pool.has(unit))
		button.pressed.connect(_on_unit_pressed.bind(unit, side))
		list.add_child(button)
	if units.is_empty():
		var none := Label.new()
		none.text = "No units"
		none.modulate = Color(1, 1, 1, 0.5)
		list.add_child(none)
	_shown_power[side] = total * (battle.defender_multiplier() if side == Battle.DEFENDER else 1.0)


func _side_color(side: int) -> Color:
	return UnitManager.PLAYERS[battle.sides[side]]["color"]
