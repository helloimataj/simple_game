# simple_game

A turn-based war game built with Godot 4.5, played on a hex-tiled globe.

## Running

Open `project.godot` in Godot 4.5 or newer and press F5. Choose a world size
and seed, then click **Generate World**.

## The world

- **Globe:** an icosahedron subdivided into hexagons, with a pentagon at each of
  the 12 icosahedron corners (a Goldberg polyhedron). Edge length can be set
  from 20 to 100 hexes, which gives 4,002 to 100,002 tiles (`10 × edge² + 2`).
- **Terrain:** an Earth-like generator. Tectonic plates collide to raise
  mountain ranges and island arcs. Sea level is set so about 29% of the surface
  is land. Climate comes from latitude, altitude, global rainfall bands and
  distance from the sea. The same seed gives the same world at any size.
- **Biomes:** Plains & Grasslands, Temperate & Boreal Forest, Jungle &
  Rainforest, Desert & Arid Scrub, Mountains & Highlands, Swamp & Marshland,
  Tundra & Arctic, plus Deep Ocean and Shallow Water. Rules text and first-pass
  gameplay stats are in `scripts/world/biomes.gd`.

## Weather and turns

Every tile has one of five weather conditions each turn: Clear, Overcast /
Mist, Heavy Rain, Mud / Deep Snow, or Storm / Blizzard. Fronts drift around
the planet and change shape from turn to turn, and wet climates get more of
them than deserts. Mud / Deep Snow is a ground condition left behind on land
after rain or storms. Rules text and numeric modifiers (visibility in hexes,
movement, ranged and melee modifiers, air and off-board support) are in
`scripts/world/weather.gd`; the simulation is in
`scripts/world/weather_system.gd`.

**Next Turn** (or Space) advances the turn, which for now only moves the
weather. The **Weather** button tints the globe by condition.

## Controls

| Action | Input |
| --- | --- |
| Spin the globe | Drag with any mouse button, or WASD / arrow keys |
| Zoom | Mouse wheel, pinch, Q / E, or - / = |
| Select a tile | Click |
| Clear selection | Esc |
| Next turn | Space, or the Next Turn button |

The camera tilts toward the horizon when zoomed in close.

## Project layout

```
scenes/main.tscn               Main scene: globe, camera, UI
scripts/main.gd                Setup screen, threaded generation, picking, HUD
scripts/globe_camera.gd        Camera that orbits the globe
scripts/world/planet.gd        Hex sphere geometry and tile adjacency
scripts/world/terrain_generator.gd  Plates, climate and biomes
scripts/world/biomes.gd        Biome colours, rules text and stats
scripts/world/weather.gd       Weather rules text, modifiers and overlay colours
scripts/world/weather_system.gd  Per-turn weather simulation
scripts/world/planet_mesh.gd   Mesh and tile-colour texture builder
shaders/                       Tile, atmosphere and starfield shaders
tests/                         Headless tests
```

Each tile's colour lives in a lookup texture rather than in the mesh, so tiles
can be recoloured cheaply later (ownership, fog of war, and so on).

## Tests

```bash
godot --headless --path . --script res://tests/test_planet.gd
godot --headless --path . --script res://tests/test_interaction.gd
```

## Debug options

Pass options after `--`, for example to generate a world straight away and save
a screenshot:

```bash
godot --path . -- --size=60 --seed=42 --autostart --view=20,0,18 --weather --turns=3 --screenshot=shot.png
```
