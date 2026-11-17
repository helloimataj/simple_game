extends Node3D
## Game entry point: world setup screen, background generation and globe view.
##
## Debug command-line options (after `--`):
##   --size=N --seed=N --autostart     generate immediately
##   --view=LAT,LON,ALT                initial camera position
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

var planet: Planet
var world_seed := 0

var _material: ShaderMaterial
var _thread: Thread
var _hovered := -1
var _selected := -1
var _pick_hint := 0
var _shown_tile := -2
var _options := {}


func _ready() -> void:
	_options = _parse_options()

	_material = ShaderMaterial.new()
	_material.shader = TILE_SHADER
	_material.set_shader_parameter("water_max_id", Biomes.Type.SHALLOW_WATER)
	planet_instance.material_override = _material

	camera.reset_view(PLANET_RADIUS)
	_build_legend()

	size_slider.min_value = Planet.MIN_FREQUENCY
	size_slider.max_value = Planet.MAX_FREQUENCY
	size_slider.value_changed.connect(_on_size_changed)
	random_seed_button.pressed.connect(_randomize_seed)
	generate_button.pressed.connect(_on_generate_pressed)
	legend_button.toggled.connect(func(on: bool) -> void: legend.visible = on)
	borders_button.toggled.connect(func(on: bool) -> void:
		_material.set_shader_parameter("border_strength", 0.35 if on else 0.0))
	new_world_button.pressed.connect(_show_setup)

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
	_report("Finishing...", 0.97)
	print("World %d (edge %d, %d tiles) generated in %d ms" % [
		gen_seed, edge, new_planet.tile_count, Time.get_ticks_msec() - t0])
	_on_world_generated.call_deferred(new_planet, arrays, colors)


func _report(text: String, value: float) -> void:
	_set_progress.call_deferred(text, value)


func _set_progress(text: String, value: float) -> void:
	loading_label.text = text
	progress_bar.value = value


func _on_world_generated(new_planet: Planet, arrays: Array, colors: PackedByteArray) -> void:
	_thread.wait_to_finish()
	planet = new_planet
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
		"Drag to spin  |  Scroll / Q E to zoom  |  WASD / arrows to rotate  |  Click to select"]

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
	if planet == null or not hud.visible:
		return
	var hovered := -1
	if get_viewport().gui_get_hovered_control() == null:
		hovered = _tile_at_screen(get_viewport().get_mouse_position())
	if hovered != _hovered:
		_hovered = hovered
		_update_highlight()
		_update_info()


func _unhandled_input(event: InputEvent) -> void:
	if planet == null or not hud.visible:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and not camera.dragged:
			_selected = _tile_at_screen(mb.position)
			_update_highlight()
			_update_info()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_selected = -1
		_update_highlight()
		_update_info()


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
