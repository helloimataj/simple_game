extends Node3D
## Game entry point: world setup screen, background generation and globe view.
##
## Debug command-line options (after `--`):
##   --size=N --seed=N --autostart     generate immediately
##   --view=LAT,LON,ALT                initial camera position
##   --sandbox                         start with costs and requirements off
##   --demo-buildings=N                give each side a capital and ~N buildings
##   --demo-units=N                    scatter about N random units
##   --weather --turns=N               show the weather overlay; skip N turns
##   --screenshot=path.png             save a screenshot after generating, then quit

const PLANET_RADIUS := 10.0
const TILE_SHADER := preload("res://shaders/planet_tiles.gdshader")

@onready var camera: GlobeCamera = $GlobeCamera
@onready var planet_instance: MeshInstance3D = $Planet
@onready var atmosphere: MeshInstance3D = $Atmosphere

@onready var setup_panel: Control = $UI/SetupPanel
@onready var size_label: Label = $UI/SetupPanel/Margin/VBox/SizeLabel
@onready var size_slider: HSlider = $UI/SetupPanel/Margin/VBox/SizeSlider
@onready var seed_edit: SpinBox = $UI/SetupPanel/Margin/VBox/SeedRow/SeedEdit
@onready var random_seed_button: Button = $UI/SetupPanel/Margin/VBox/SeedRow/RandomSeedButton
@onready var generate_button: Button = $UI/SetupPanel/Margin/VBox/GenerateButton

@onready var loading_panel: Control = $UI/LoadingPanel
@onready var loading_label: Label = $UI/LoadingPanel/Margin/VBox/LoadingLabel
@onready var progress_bar: ProgressBar = $UI/LoadingPanel/Margin/VBox/ProgressBar

@onready var hud: Control = $UI/Hud
@onready var tile_info: RichTextLabel = $UI/Hud/InfoPanel/Margin/TileInfo
@onready var legend: Control = $UI/Hud/TopRight/Legend
@onready var legend_entries: VBoxContainer = $UI/Hud/TopRight/Legend/Margin/Entries
@onready var legend_button: Button = $UI/Hud/TopRight/Buttons/LegendButton
@onready var borders_button: Button = $UI/Hud/TopRight/Buttons/BordersButton
@onready var new_world_button: Button = $UI/Hud/TopRight/Buttons/NewWorldButton
@onready var world_info: Label = $UI/Hud/WorldInfo
@onready var weather_button: Button = $UI/Hud/TopRight/Buttons/WeatherButton
@onready var next_turn_button: Button = $UI/Hud/NextTurnButton
@onready var unit_layer: UnitLayer = $Units
@onready var building_layer: BuildingLayer = $Buildings
@onready var build_option: OptionButton = $UI/Hud/UnitBar/Margin/Row/BuildOption
@onready var sandbox_check: CheckBox = $UI/Hud/UnitBar/Margin/Row/SandboxCheck
@onready var resource_text: RichTextLabel = $UI/Hud/ResourceBar/Margin/Text
@onready var attack_button: Button = $UI/Hud/UnitBar/Margin/Row/AttackButton
@onready var unit_type_buttons: HBoxContainer = $UI/Hud/UnitBar/Margin/Row/TypeButtons
@onready var remove_unit_button: Button = $UI/Hud/UnitBar/Margin/Row/RemoveButton
@onready var side_option: OptionButton = $UI/Hud/UnitBar/Margin/Row/SideOption

var planet: Planet
var weather: WeatherSystem
var game: GameState
var units: UnitManager
var buildings: BuildingManager
var world_seed := 0

var _material: ShaderMaterial
var _thread: Thread
var _hovered := -1
var _selected := -1
var _pick_hint := 0
var _shown_tile := -2
var _options := {}
var _weather_texture: ImageTexture
var weather_legend: VBoxContainer
const TOOL_NONE := -1
const TOOL_REMOVE := -2
const TOOL_ATTACK := -3
## Tools from here up build BuildingTypes.Type (tool - TOOL_BUILD).
const TOOL_BUILD := 100
## Unit type being trained by clicking, TOOL_BUILD + a building type, or
## TOOL_NONE / TOOL_REMOVE.
var _tool := TOOL_NONE
var _tool_group: ButtonGroup
var battle_panel: BattlePanel
var _battle_rng := RandomNumberGenerator.new()
var _notice := ""


func _ready() -> void:
	_options = _parse_options()

	_material = ShaderMaterial.new()
	_material.shader = TILE_SHADER
	_material.set_shader_parameter("water_max_id", Biomes.Type.SHALLOW_WATER)
	planet_instance.material_override = _material

	camera.reset_view(PLANET_RADIUS)
	_build_legend()
	_build_unit_bar()
	battle_panel = BattlePanel.new()
	$UI.add_child(battle_panel)
	battle_panel.closed.connect(_on_battle_closed)

	size_slider.min_value = Planet.MIN_FREQUENCY
	size_slider.max_value = Planet.MAX_FREQUENCY
	size_slider.value_changed.connect(_on_size_changed)
	random_seed_button.pressed.connect(_randomize_seed)
	generate_button.pressed.connect(_on_generate_pressed)
	legend_button.toggled.connect(func(on: bool) -> void: legend.visible = on)
	borders_button.toggled.connect(func(on: bool) -> void:
		_material.set_shader_parameter("border_strength", 0.35 if on else 0.0))
	new_world_button.pressed.connect(_show_setup)
	weather_button.toggled.connect(_on_weather_toggled)
	next_turn_button.pressed.connect(_on_next_turn)

	_randomize_seed()
	if _options.has("size"):
		size_slider.value = int(_options["size"])
	if _options.has("seed"):
		seed_edit.value = int(_options["seed"])
	_on_size_changed(size_slider.value)
	_show_setup()

	if _options.has("autostart"):
		_on_generate_pressed()


func _exit_tree() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()


# --- Setup -------------------------------------------------------------------

func _show_setup() -> void:
	setup_panel.visible = true
	loading_panel.visible = false
	hud.visible = false
	generate_button.grab_focus()


func _randomize_seed() -> void:
	seed_edit.value = randi_range(1, int(seed_edit.max_value))


func _on_size_changed(value: float) -> void:
	var edge := int(value)
	size_label.text = "World size: %d hexes per edge  (%s tiles)" % [
		edge, _thousands(Planet.tile_count_for(edge))]


func _on_generate_pressed() -> void:
	if _thread and _thread.is_started():
		return
	var edge := int(size_slider.value)
	world_seed = int(seed_edit.value)
	setup_panel.visible = false
	hud.visible = false
	loading_panel.visible = true
	_set_progress("Generating world...", 0.0)
	_thread = Thread.new()
	_thread.start(_generate_world.bind(edge, world_seed))


# --- Generation (runs on a worker thread) -------------------------------------

func _generate_world(edge: int, gen_seed: int) -> void:
	var t0 := Time.get_ticks_msec()
	var new_planet := Planet.new()
	new_planet.build(edge, func(f: float) -> void: _report("Building tiles...", f * 0.3))
	TerrainGenerator.generate(new_planet, gen_seed,
		func(f: float) -> void: _report("Shaping continents and climate...", 0.3 + f * 0.45))
	_report("Building globe mesh...", 0.75)
	var arrays := PlanetMesh.build_arrays(new_planet, PLANET_RADIUS)
	var colors := PlanetMesh.build_color_data(new_planet)
	_report("Brewing weather...", 0.92)
	var new_weather := WeatherSystem.new()
	new_weather.setup(new_planet, gen_seed)
	_report("Finishing...", 0.97)
	print("World %d (edge %d, %d tiles) generated in %d ms" % [
		gen_seed, edge, new_planet.tile_count, Time.get_ticks_msec() - t0])
	_on_world_generated.call_deferred(new_planet, new_weather, arrays, colors)


func _report(text: String, value: float) -> void:
	_set_progress.call_deferred(text, value)


func _set_progress(text: String, value: float) -> void:
	loading_label.text = text
	progress_bar.value = value


func _on_world_generated(new_planet: Planet, new_weather: WeatherSystem,
		arrays: Array, colors: PackedByteArray) -> void:
	_thread.wait_to_finish()
	planet = new_planet
	weather = new_weather
	game = GameState.new(planet)
	game.sandbox = sandbox_check.button_pressed or _options.has("sandbox")
	units = game.units
	buildings = game.buildings
	game.changed.connect(_on_game_changed)
	unit_layer.setup(planet, units, PLANET_RADIUS)
	building_layer.setup(planet, buildings, PLANET_RADIUS)
	if _options.has("demo-buildings"):
		_scatter_demo_buildings(int(_options["demo-buildings"]))
	_update_resources()
	if _options.has("demo-units"):
		_scatter_demo_units(int(_options["demo-units"]))
	_weather_texture = null
	_refresh_weather()
	if _options.has("weather"):
		weather_button.button_pressed = true
	for i in int(_options.get("turns", 0)):
		_on_next_turn()
	planet_instance.mesh = PlanetMesh.create_mesh(arrays)
	_material.set_shader_parameter("tile_colors", PlanetMesh.create_color_texture(planet, colors))
	atmosphere.visible = true

	_hovered = -1
	_selected = -1
	_pick_hint = 0
	_shown_tile = -2
	_update_highlight()
	world_info.text = "Seed %d  |  %d hexes per edge  |  %s tiles\n%s" % [
		world_seed, planet.frequency, _thousands(planet.tile_count),
		"Drag to spin  |  Scroll / Q E to zoom  |  WASD / arrows to rotate  |  Click to select  |  Space: next turn"]

	loading_panel.visible = false
	hud.visible = true
	camera.reset_view(PLANET_RADIUS)
	if _options.has("view"):
		var v: PackedStringArray = str(_options["view"]).split(",")
		if v.size() >= 3:
			camera.set_view(float(v[0]), float(v[1]), float(v[2]))
	_update_info()

	if _options.has("screenshot"):
		_take_screenshot(str(_options["screenshot"]))


# --- Interaction ---------------------------------------------------------------

func _process(_delta: float) -> void:
	if planet == null or not hud.visible or battle_panel.visible:
		return
	var hovered := -1
	if get_viewport().gui_get_hovered_control() == null:
		hovered = _tile_at_screen(get_viewport().get_mouse_position())
	if hovered != _hovered:
		_hovered = hovered
		_update_highlight()
		_update_info()


func _unhandled_input(event: InputEvent) -> void:
	if planet == null or not hud.visible or battle_panel.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not camera.dragged:
			var previous := _selected
			_selected = _tile_at_screen(mb.position)
			_notice = ""
			if _selected >= 0 and _tool == TOOL_ATTACK:
				_try_attack(previous, _selected)
			elif _selected >= 0 and _tool != TOOL_NONE:
				_use_tool_on(_selected)
			_update_highlight()
			_shown_tile = -2
			_update_info()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_selected = -1
			_update_highlight()
			_update_info()
		elif event.keycode == KEY_SPACE:
			_on_next_turn()


# --- Units ---------------------------------------------------------------------

func _build_unit_bar() -> void:
	var group := ButtonGroup.new()
	group.allow_unpress = true
	_tool_group = group
	for type in UnitTypes.count():
		var button := Button.new()
		button.text = UnitTypes.display_name(type)
		button.toggle_mode = true
		button.button_group = group
		button.tooltip_text = UnitTypes.summary(type)
		button.toggled.connect(_on_tool_toggled.bind(type))
		unit_type_buttons.add_child(button)
	remove_unit_button.button_group = group
	remove_unit_button.toggled.connect(_on_tool_toggled.bind(TOOL_REMOVE))
	attack_button.button_group = group
	attack_button.toggled.connect(_on_tool_toggled.bind(TOOL_ATTACK))
	for i in UnitManager.PLAYERS.size():
		side_option.add_item(UnitManager.PLAYERS[i]["name"], i)
	side_option.item_selected.connect(func(_index: int) -> void: _update_resources())
	sandbox_check.toggled.connect(func(on: bool) -> void:
		if game != null:
			game.sandbox = on)

	# Build menu: every building type, grouped by category.
	build_option.add_item("Build...", TOOL_NONE)
	var category := -1
	for type in BuildingTypes.count():
		var data := BuildingTypes.info(type)
		if data["category"] != category:
			category = data["category"]
			build_option.add_separator(BuildingTypes.CATEGORY_NAMES[category])
		build_option.add_item(data["name"], type)
		build_option.set_item_tooltip(build_option.item_count - 1, BuildingTypes.summary(type))
	build_option.item_selected.connect(_on_build_selected)


func _on_tool_toggled(on: bool, tool: int) -> void:
	if on:
		_tool = tool
		build_option.select(0)
	elif _tool == tool:
		_tool = TOOL_NONE


func _on_build_selected(index: int) -> void:
	var type := build_option.get_item_id(index)
	var pressed := _tool_group.get_pressed_button()
	if type >= 0 and pressed != null:
		pressed.button_pressed = false
	if type >= 0:
		_tool = TOOL_BUILD + type
	elif _tool >= TOOL_BUILD:
		_tool = TOOL_NONE


func _current_side() -> int:
	return side_option.get_selected_id()


## Trains a unit, builds a building or removes something on a clicked tile,
## depending on the active tool.
func _use_tool_on(tile: int) -> void:
	var side := _current_side()
	if _tool == TOOL_REMOVE:
		var stack := units.units_at(tile)
		var here := buildings.buildings_at(tile)
		if not stack.is_empty():
			units.remove_unit(stack[-1])
		elif not here.is_empty():
			buildings.remove_building(here[-1])
		else:
			_notice = "Nothing here to remove"
	elif _tool >= TOOL_BUILD:
		var type := _tool - TOOL_BUILD
		var reason := game.build_block_reason(type, side, tile)
		if reason != "":
			_notice = "Can't build here: " + reason
		else:
			game.build(type, side, tile)
	else:
		var reason := game.train_block_reason(_tool, side, tile)
		if reason != "":
			_notice = "Can't place here: " + reason
		else:
			game.train(_tool, side, tile)


## Attack tool: `from` is the previously selected tile, `target` the one just clicked.
func _try_attack(from: int, target: int) -> void:
	var side := _current_side()
	var reason := Battle.start_block_reason(game, side, from, target)
	if reason != "":
		# Clicking one of your own stacks just picks it as the attacking tile.
		var own := units.units_at(target).any(func(u: Unit) -> bool: return u.owner == side)
		_notice = "Now click an adjacent tile with enemy units" if own else "Can't attack: " + reason
		return
	battle_panel.open(Battle.new(game, side, from, target, weather, _battle_rng))


func _on_battle_closed() -> void:
	_shown_tile = -2
	_update_highlight()
	_update_info()
	_update_resources()


func _on_game_changed() -> void:
	_shown_tile = -2
	_update_info()
	_update_resources()


## Stockpile, next turn's net change and power for the selected side.
func _update_resources() -> void:
	if game == null:
		return
	var side := _current_side()
	var player: Dictionary = UnitManager.PLAYERS[side]
	var income := game.income_for(side)
	var parts: Array[String] = []
	for type in ResourceTypes.count():
		var net: int = income[type]
		var net_text := ""
		if net != 0:
			net_text = " [color=#%s]%+d[/color]" % ["8fd18f" if net > 0 else "ff8a80", net]
		parts.append("[color=#%s]%s[/color] [b]%s[/b]%s" % [
			ResourceTypes.color(type).to_html(false), ResourceTypes.display_name(type),
			_thousands(game.stock[side][type]), net_text])
	var power := game.power_for(side)
	parts.append("[color=#%s]Power[/color] [b]%d/%d[/b]" % [
		"ff8a80" if power.x < power.y else "f2f27a", power.x, power.y])
	resource_text.text = "[center][color=#%s]■[/color] %s%s   %s[/center]" % [
		(player["color"] as Color).to_html(false), player["name"],
		" (sandbox)" if game.sandbox else "", "   ".join(parts)]
	resource_text.tooltip_text = "Stockpile and change next turn. Power is supply / demand."


## Debug: gives each side a capital and some random buildings around it.
func _scatter_demo_buildings(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 99
	var was_sandbox := game.sandbox
	game.sandbox = true
	for side in UnitManager.PLAYERS.size():
		var home := -1
		for attempt in 2000:
			var tile := rng.randi_range(0, planet.tile_count - 1)
			if game.build(BuildingTypes.Type.CAPITAL, side, tile) != null:
				home = tile
				break
		if home < 0:
			continue
		# Spread outwards from the capital.
		var frontier: Array[int] = [home]
		var placed := 0
		var attempts := 0
		while placed < count and attempts < count * 40:
			attempts += 1
			var tile: int = frontier[rng.randi_range(0, frontier.size() - 1)]
			var nbs := planet.get_neighbors(tile)
			var next := nbs[rng.randi_range(0, nbs.size() - 1)]
			if not frontier.has(next) and not Biomes.is_water(planet.biomes[next]):
				frontier.append(next)
			var type := rng.randi_range(0, BuildingTypes.count() - 1)
			if game.build(type, side, tile) != null:
				placed += 1
	game.sandbox = was_sandbox


## Debug: drops `count` random units on valid tiles.
func _scatter_demo_units(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 50:
		attempts += 1
		var tile := rng.randi_range(0, planet.tile_count - 1)
		var type := rng.randi_range(0, UnitTypes.count() - 1)
		var side := rng.randi_range(0, UnitManager.PLAYERS.size() - 1)
		if not units.can_place(type, tile):
			continue
		# Build small mixed stacks around the spot.
		for i in rng.randi_range(1, 4):
			units.add_unit(type, side, tile)
			placed += 1
		for nb in planet.get_neighbors(tile):
			var other := rng.randi_range(0, UnitTypes.count() - 1)
			if rng.randf() < 0.5 and units.can_place(other, nb):
				units.add_unit(other, side, nb)
				placed += 1
				if units.add_unit(type, side, nb) != null:
					placed += 1


# --- Turns and weather -----------------------------------------------------------

func _on_next_turn() -> void:
	if planet == null or weather == null:
		return
	game.end_turn()
	weather.advance()
	_refresh_weather()


## Pushes the current weather to the globe overlay and the HUD.
func _refresh_weather() -> void:
	var image := Image.create_from_data(PlanetMesh.TEXTURE_WIDTH, PlanetMesh.texture_height(planet),
		false, Image.FORMAT_RGBA8, weather.build_overlay_data())
	if _weather_texture == null:
		_weather_texture = ImageTexture.create_from_image(image)
		_material.set_shader_parameter("tile_weather", _weather_texture)
	else:
		_weather_texture.update(image)
	next_turn_button.text = "Next Turn  (turn %d)" % weather.turn
	_shown_tile = -2
	_update_info()


func _on_weather_toggled(on: bool) -> void:
	_material.set_shader_parameter("show_weather", on)
	weather_legend.visible = on


## Tile under a screen position, or -1 if the cursor misses the globe.
func _tile_at_screen(screen_pos: Vector2) -> int:
	var origin := camera.project_ray_origin(screen_pos)
	var dir := camera.project_ray_normal(screen_pos)
	var b := origin.dot(dir)
	var c := origin.length_squared() - PLANET_RADIUS * PLANET_RADIUS
	var disc := b * b - c
	if disc < 0.0:
		return -1
	var t := -b - sqrt(disc)
	if t < 0.0:
		return -1
	var tile := planet.find_tile(origin + dir * t, _pick_hint)
	_pick_hint = tile
	return tile


func _update_highlight() -> void:
	_material.set_shader_parameter("hovered_tile", _hovered)
	_material.set_shader_parameter("selected_tile", _selected)


func _update_info() -> void:
	var tile := _hovered if _hovered >= 0 else _selected
	if tile == _shown_tile:
		return
	_shown_tile = tile
	if tile < 0 or planet == null:
		tile_info.text = "[color=#bbbbbb]Hover over or click a tile[/color]"
		return

	var biome := planet.biomes[tile]
	var data := Biomes.info(biome)
	var dir := planet.centers[tile]
	var lat := rad_to_deg(Planet.latitude_of(dir))
	var lon := rad_to_deg(Planet.longitude_of(dir))
	var e := planet.elevation[tile]
	var height_text := ("%s m" % _thousands(roundi(e * 8000.0))) if e >= 0.0 \
		else ("depth %s m" % _thousands(roundi(-e * 6000.0)))
	var temp_c := roundi(lerpf(-35.0, 32.0, planet.temperature[tile]))

	var lines: Array[String] = []
	lines.append("[font_size=20][color=#%s]■[/color] [b]%s[/b][/font_size]" % [
		(data["color"] as Color).to_html(false), data["name"]])
	lines.append("[color=#aaaaaa]Tile %d%s  |  %.1f° %s, %.1f° %s[/color]" % [
		tile, " (pentagon)" if planet.degree(tile) == 5 else "",
		absf(lat), "N" if lat >= 0.0 else "S", absf(lon), "E" if lon >= 0.0 else "W"])
	lines.append("[color=#aaaaaa]%s  |  %d °C avg  |  %d%% moisture[/color]" % [
		height_text, temp_c, roundi(planet.moisture[tile] * 100.0)])
	lines.append("")
	lines.append("[b]Movement:[/b] " + data["movement"])
	lines.append("[b]Combat & vision:[/b] " + data["combat"])
	lines.append("[b]Strategic role:[/b] " + data["strategic"])
	if weather != null:
		var w := weather.weather_at(tile)
		var wd := Weather.info(w)
		var local := Weather.local_name(w, biome, planet.temperature[tile])
		var title: String = wd["name"]
		if not title.contains(local):
			title = "%s (%s)" % [local, title]
		lines.append("")
		lines.append("[font_size=17][b]Weather: %s[/b][/font_size]" % title)
		lines.append("[b]Movement:[/b] " + wd["movement"])
		lines.append("[b]Visibility:[/b] " + wd["visibility"])
		lines.append("[b]Combat & ranged:[/b] " + wd["combat"])
		lines.append("[b]Air / support:[/b] " + wd["air"])
	if buildings != null and not buildings.buildings_at(tile).is_empty():
		var here := buildings.buildings_at(tile)
		var owner: Dictionary = UnitManager.PLAYERS[here[0].owner]
		var names: Array[String] = []
		for building in here:
			names.append("[color=#%s]■[/color] %s" % [
				BuildingTypes.category_color(building.type).to_html(false), building.display_name()])
		lines.append("")
		lines.append("[font_size=17][b]Buildings: %d[/b][/font_size]  [color=#%s]%s[/color]" % [
			here.size(), (owner["color"] as Color).to_html(false), owner["name"]])
		lines.append(",  ".join(names))
	if units != null:
		var groups := units.stack_summary(tile)
		if not groups.is_empty():
			var keys := groups.keys()
			keys.sort()
			lines.append("")
			lines.append("[font_size=17][b]Units here: %d[/b][/font_size]" % units.units_at(tile).size())
			for key in keys:
				var player: Dictionary = UnitManager.PLAYERS[key[0]]
				var hp := 0
				for unit in units.units_at(tile):
					if unit.owner == key[0] and unit.type == key[1]:
						hp += unit.hit_points
				var full: int = groups[key] * UnitTypes.info(key[1])["power"]
				lines.append("[color=#%s]■[/color] %s: %d × %s  [color=#aaaaaa]HP %d/%d[/color]" % [
					(player["color"] as Color).to_html(false), player["name"],
					groups[key], UnitTypes.display_name(key[1]), hp, full])
	if _notice != "" and tile == _selected:
		lines.append("\n[color=#ff8a80]%s[/color]" % _notice)
	if tile == _selected and _hovered < 0:
		lines.append("\n[color=#ffd23f]Selected[/color]  [color=#888888](Esc to clear)[/color]")
	tile_info.text = "\n".join(lines)


func _build_legend() -> void:
	for child in legend_entries.get_children():
		child.queue_free()
	for b in Biomes.count():
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		swatch.color = Biomes.color(b)
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = Biomes.display_name(b)
		row.add_child(swatch)
		row.add_child(label)
		legend_entries.add_child(row)

	# Weather overlay colours, shown only while the overlay is on.
	weather_legend = VBoxContainer.new()
	weather_legend.visible = false
	weather_legend.add_child(HSeparator.new())
	for w in Weather.count():
		if w == Weather.Type.CLEAR:
			continue
		var row := HBoxContainer.new()
		var swatch := ColorRect.new()
		var overlay := Weather.overlay_color(w)
		swatch.color = Color(overlay.r, overlay.g, overlay.b)
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var label := Label.new()
		label.text = Weather.info(w)["name"]
		row.add_child(swatch)
		row.add_child(label)
		weather_legend.add_child(row)
	legend_entries.add_child(weather_legend)


# --- Utilities -----------------------------------------------------------------

func _take_screenshot(path: String) -> void:
	for i in 10:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(path)
	print("Saved screenshot to ", path)
	get_tree().quit()


static func _parse_options() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var parts := arg.substr(2).split("=", true, 1)
		out[parts[0]] = parts[1] if parts.size() > 1 else true
	return out


static func _thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if value < 0 else "") + s + out
