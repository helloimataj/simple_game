extends SceneTree
## Drives the main scene with simulated mouse input.
## Run: godot --headless --path . --script res://tests/test_interaction.gd

var failures := 0


func _init() -> void:
	_run.call_deferred()


func _expect(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		push_error("FAIL: " + msg)
	else:
		print("ok - ", msg)


func _run() -> void:
	# Headless windows are tiny by default; give the UI room so the screen
	# centre is over the globe rather than a button.
	root.size = Vector2i(1280, 720)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	main.size_slider.value = 20
	main.seed_edit.value = 5
	main.players_spin.value = 6
	main._on_generate_pressed()
	var waited := 0
	while main.planet == null and waited < 600:
		await process_frame
		waited += 1
	_expect(main.planet != null, "world generates")
	_expect(Players.count() == int(main.players_spin.value) and main.side_option.item_count == Players.count(),
		"the chosen number of players is in the game")
	_expect(main.game.start_tiles.size() == Players.count(), "every player has a starting capital")
	var capital_dir: Vector3 = main.planet.centers[main.game.capital_of(0)]
	_expect(capital_dir.angle_to(main.camera.position.normalized()) < 0.01, "the view opens on the first player's capital")
	main.side_option.select(1)
	main.side_option.item_selected.emit(1)
	capital_dir = main.planet.centers[main.game.capital_of(1)]
	_expect(capital_dir.angle_to(main.camera.position.normalized()) < 0.01, "switching player turns the globe to their capital")
	main.side_option.select(0)
	main.side_option.item_selected.emit(0)
	_expect(main.hud.visible, "HUD shown after generation")

	var cam: GlobeCamera = main.camera
	var center := root.get_visible_rect().size / 2.0

	# Drag right: the camera should move west (longitude decreases).
	var lon_before := cam.longitude
	_mouse_button(center, true)
	for i in 10:
		_mouse_motion(center + Vector2(10 * (i + 1), 0), Vector2(10, 0))
	_mouse_button(center + Vector2(100, 0), false)
	await process_frame
	var lon_change := wrapf(cam.longitude - lon_before, -180.0, 180.0)
	_expect(lon_change < -1.0, "dragging right spins the globe (lon %.1f -> %.1f)" % [lon_before, cam.longitude])
	_expect(main._selected == -1, "a drag does not select a tile")

	# Scroll in: altitude should drop.
	var alt_before := cam.altitude
	for i in 3:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_WHEEL_UP
		ev.pressed = true
		ev.position = center
		root.push_input(ev)
	for i in 60:
		await process_frame
	_expect(cam.altitude < alt_before * 0.8, "scrolling zooms in (alt %.1f -> %.1f)" % [alt_before, cam.altitude])

	# Click the centre of the screen: selects the tile under the view centre.
	_mouse_button(center, true)
	_mouse_button(center, false)
	await process_frame
	var expected: int = main.planet.find_tile(cam.position)
	_expect(main._selected >= 0, "clicking selects a tile")
	var sel_dir: Vector3 = main.planet.centers[main._selected]
	_expect(sel_dir.angle_to(cam.position.normalized()) < main.planet.tile_angle() * 3.0,
		"selected tile is under the cursor (got %d, centre tile %d)" % [main._selected, expected])
	_expect(main.tile_info.text.contains(Biomes.display_name(main.planet.biomes[main._selected])),
		"info panel shows the tile's biome")

	# Next turn advances the weather; the info panel reports it.
	var turn_before: int = main.weather.turn
	main.next_turn_button.pressed.emit()
	await process_frame
	_expect(main.weather.turn == turn_before + 1, "Next Turn advances the turn")
	_expect(main.next_turn_button.text.contains(str(turn_before + 1)), "turn number shown on the button")
	_expect(main.tile_info.text.contains("Weather:"), "info panel shows the tile's weather")
	main.weather_button.button_pressed = true
	_expect(main._material.get_shader_parameter("show_weather") == true, "Weather button turns the overlay on")

	# Placing units with the toolbar: click places on valid tiles only.
	var tile: int = main._selected
	var water := Biomes.is_water(main.planet.biomes[tile])
	var valid_type := UnitTypes.Type.NAVAL if water else UnitTypes.Type.INFANTRY
	var invalid_type := UnitTypes.Type.INFANTRY if water else UnitTypes.Type.NAVAL
	var buttons: Array = main.unit_type_buttons.get_children()
	buttons[valid_type].button_pressed = true
	_mouse_button(center, true)
	_mouse_button(center, false)
	await process_frame
	_expect(main.units.units_at(tile).is_empty(), "units cannot be trained without a production building")
	_expect(main.tile_info.text.contains("must be trained"), "info panel says which building is needed")
	main.sandbox_check.button_pressed = true
	_expect(main.game.sandbox, "Sandbox checkbox turns sandbox mode on")
	buttons[valid_type].button_pressed = true
	for i in 3:
		_mouse_button(center, true)
		_mouse_button(center, false)
	await process_frame
	_expect(main.units.units_at(tile).size() == 3, "three clicks stack three units on the tile")
	_expect(main.tile_info.text.contains("Units here: 3"), "info panel lists the stack")
	buttons[invalid_type].button_pressed = true
	_mouse_button(center, true)
	_mouse_button(center, false)
	await process_frame
	_expect(main.units.units_at(tile).size() == 3, "invalid unit type is not placed")
	_expect(main.tile_info.text.contains("Can't place here"), "info panel explains why")
	main.remove_unit_button.button_pressed = true
	_mouse_button(center, true)
	_mouse_button(center, false)
	await process_frame
	_expect(main.units.units_at(tile).size() == 2, "Remove tool removes one unit")
	main.remove_unit_button.button_pressed = false
	_expect(main._tool == main.TOOL_NONE, "untoggling returns to plain selection")

	# Build menu: choosing a building makes clicks build it.
	var farm_index := -1
	for i in main.build_option.item_count:
		if main.build_option.get_item_id(i) == BuildingTypes.Type.FARM \
				and not main.build_option.is_item_separator(i):
			farm_index = i
	buttons[0].button_pressed = true
	main.build_option.select(farm_index)
	main.build_option.item_selected.emit(farm_index)
	_expect(main._tool == main.TOOL_BUILD + BuildingTypes.Type.FARM, "build menu selects the building tool")
	_expect(not buttons[0].button_pressed, "choosing a building releases the unit buttons")
	_mouse_button(center, true)
	_mouse_button(center, false)
	await process_frame
	var farm_ok: bool = main.buildings.can_place(BuildingTypes.Type.FARM, 0, tile) \
		or main.buildings.has_type(tile, BuildingTypes.Type.FARM)
	_expect(main.buildings.has_type(tile, BuildingTypes.Type.FARM) == farm_ok
		and (farm_ok or main.tile_info.text.contains("Can't build here")),
		"clicking builds the farm where allowed, or explains why not")
	if farm_ok:
		_expect(main.tile_info.text.contains("Buildings: 1"), "info panel lists the building")

	# Resource bar and per-turn income.
	_expect(main.resource_text.text.contains("Money") and main.resource_text.text.contains("Power"),
		"resource bar shows the stockpile and power")
	var money: int = main.game.stock[0][ResourceTypes.Type.MONEY]
	var expected_net: int = main.game.income_for(0)[ResourceTypes.Type.MONEY]
	main.next_turn_button.pressed.emit()
	await process_frame
	_expect(main.game.stock[0][ResourceTypes.Type.MONEY] == maxi(money + expected_net, 0),
		"Next Turn applies income and upkeep (%d %+d)" % [money, expected_net])

	await _check_battle(main)

	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


## Plays a whole battle through the battle screen's buttons.
func _check_battle(main: Node) -> void:
	var planet: Planet = main.planet
	var from := -1
	var target := -1
	for t in planet.tile_count:
		if planet.biomes[t] != Biomes.Type.PLAINS or not main.units.units_at(t).is_empty():
			continue
		for nb in planet.get_neighbors(t):
			if planet.biomes[nb] == Biomes.Type.PLAINS and main.units.units_at(nb).is_empty():
				from = t
				target = nb
		if from >= 0:
			break
	_expect(from >= 0, "found two adjacent plains tiles")
	main.game.sandbox = true
	for i in 4:
		main.game.train(UnitTypes.Type.ARMOR, 0, from)
	main.game.train(UnitTypes.Type.INFANTRY, 1, target)
	main.game.train(UnitTypes.Type.INFANTRY, 1, target)

	main.side_option.select(0)
	main._try_attack(target, from)
	_expect(not main.battle_panel.visible, "cannot attack from a tile without your units")
	main._try_attack(from, target)
	var panel: BattlePanel = main.battle_panel
	_expect(panel.visible and panel.stage == BattlePanel.Stage.COMMIT_ATTACKER, "attack opens the battle screen")
	main._on_next_turn.call()
	var turn: int = main.weather.turn
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	root.push_input(space)
	_expect(main.weather.turn == turn, "the turn cannot advance from the keyboard during a battle")

	panel._primary.pressed.emit()
	_expect(panel.stage == BattlePanel.Stage.COMMIT_DEFENDER, "attacker commits, then the defender chooses")
	panel._primary.pressed.emit()
	_expect(panel.stage == BattlePanel.Stage.ROLL and panel.battle.committed[0].size() == 4
		and panel.battle.committed[1].size() == 2, "both sides committed everything")
	var steps := 0
	var saw_assign := false
	var saw_retreat := false
	while panel.stage != BattlePanel.Stage.FINISHED and steps < 200:
		steps += 1
		if panel.stage == BattlePanel.Stage.ASSIGN:
			saw_assign = true
			# Click a unit row to take the damage instead of auto-assigning.
			var side: int = panel.battle.current_damage()["side"]
			for row in panel._columns[side].get_children():
				if row is Button and not row.disabled:
					row.pressed.emit()
					break
		else:
			saw_retreat = saw_retreat or panel.stage == BattlePanel.Stage.RETREAT_ATTACKER
			panel._primary.pressed.emit()
	_expect(panel.stage == BattlePanel.Stage.FINISHED, "battle screen reaches a result (%d steps)" % steps)
	_expect(saw_assign, "damage was assigned by clicking units")
	_expect(panel.battle.winner == Battle.ATTACKER, "four tanks on plains beat two infantry")
	panel._primary.pressed.emit()
	await process_frame
	_expect(not panel.visible, "Close hides the battle screen")
	var holders: Array = main.units.units_at(target)
	_expect(not holders.is_empty() and holders.all(func(u: Unit) -> bool: return u.owner == 0),
		"the winners hold the tile")


func _mouse_button(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)


func _mouse_motion(pos: Vector2, rel: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	ev.relative = rel
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(ev)
