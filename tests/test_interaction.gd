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
	main._on_generate_pressed()
	var waited := 0
	while main.planet == null and waited < 600:
		await process_frame
		waited += 1
	_expect(main.planet != null, "world generates")
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
	_expect(cam.longitude < lon_before - 1.0, "dragging right spins the globe (lon %.1f -> %.1f)" % [lon_before, cam.longitude])
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

	print("ALL TESTS PASSED" if failures == 0 else "%d TEST(S) FAILED" % failures)
	quit(1 if failures > 0 else 0)


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
