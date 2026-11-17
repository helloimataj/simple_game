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

## Units

Five basic unit types, defined in `scripts/units/unit_types.gd` (specialised
variants will build on these):

| Unit | Role | May occupy |
| --- | --- | --- |
| Infantry | Cheap and flexible; strong in close terrain, weak in the open against armor | Any land |
| Armor | Main attack unit; fast and strong on open ground, expensive | Land except mountains |
| Aircraft | Fast, reaches anywhere, hits ground and naval units hard; can't hold territory | Anywhere |
| Naval | Controls the seas, carries troops, bombards coasts | Water only |
| Artillery | Free round before a battle; half power when defending | Land except mountains |

Any number of units can share a tile. A unit can only be on a tile its type
may occupy; this comes from each biome's movement costs, so armor is kept out
of mountains because they are impassable to vehicles.

There is no movement yet. Units are trained with the **Place** bar
at the bottom of the screen: pick a unit type and a side, then click a tile on
or next to that side's production building (Barracks for infantry, Factory for
armor and artillery, Airbase for aircraft, Shipyard for naval). Hover a unit button to see
its stats, cost and upkeep.

## Combat

Rules are in `scripts/combat/battle.gd`; the screen is
`scripts/ui/battle_panel.gd`.

To attack: select a tile with your units, turn on **Attack**, and click an
adjacent tile with enemy units.

1. **Commit.** The attacker picks units from that one adjacent tile, then the
   defender picks. Defenders left out retreat to an adjacent safe tile, or are
   lost if there is none.
2. **Roll.** Total = attacker power + defender power. The roll is drawn from a
   normal distribution centred on Total / 2 with a standard deviation of 15%
   of Total, clamped to 0..Total. The attacker owns 0..attacker power and the
   defender owns the rest.
3. **Damage.** The side whose zone the roll lands in deals damage equal to the
   distance from the roll to the dividing line, rounded. The damaged player
   assigns it; a unit absorbs as much as it can before the rest moves on.
4. **Retreat.** Both players choose units to pull out, hidden from each other,
   then reveal together. Retreating units take a pursuit hit of 25% of the
   power of the enemy that stays.
5. Repeat until one side has nothing left in the fight. If the attacker wins,
   its ground units move in and capture the tile's buildings.

A unit's power is its remaining hit points times its modifiers:

| Modifier | Effect |
| --- | --- |
| Infantry | x1.5 in cities, forest, jungle and mountains |
| Armor | x1.5 on plains, desert and tundra; x0.75 in cities |
| Artillery | Free unanswered round before round 1; x0.5 when defending |
| Aircraft | Joins from one of its side's airbases within 12 hexes; enemy air defense within 3 hexes fires on it first |
| Naval | Bombards land battles within 2 hexes; enemy coastal batteries within 3 hexes fire on it first |
| Defender | x1.2, +0.3 with fortifications, +0.2 in a city |
| Out of supply | x0.5 unless within reach of a Supply Depot or Capital (4 hexes), Shipyard (3) or Airbase (2) of its side |
| Weather | Heavy rain and mud ground air support; storms also stop bombardment |

A tile is a city if it has a Capital or Administrative Center, or four other
buildings (not counting roads, bridges, fortifications or farms).

## Buildings

30 building types in six categories (military production, economy, defense,
infrastructure, strategic, government), defined in
`scripts/buildings/building_types.gd`. Pick one from the **Build...** menu and
click a tile.

- A tile can hold any number of buildings, but only one of each type, and all
  must belong to the same side.
- Most buildings need land. Shipyards, trade ports and coastal batteries need
  land next to water. Bridges go on shallow water next to land. Farms can't be
  built on mountains, desert or tundra.
- Capital, Intelligence HQ and Space Center are limited to one per side.
- A road lets vehicles into mountains; a bridge lets land units onto its
  water tile.
- **Remove** takes the newest unit off a clicked tile, or the newest building
  if the tile has no units.

Effects that depend on systems not built yet (vision, research, missiles,
morale) are stored as numbers under each building's `effects`.

## Resources and economy

Seven stockpiled resources: Money, Food, Materials, Rare Earths, Uranium, Fuel
and Production (`scripts/economy/resource_types.gd`). Every unit and building
has a build cost and a per-turn upkeep. The rules are in
`scripts/game_state.gd`:

- Each side starts with a stockpile and pays costs from it.
- **Next Turn** adds each side's building output and subtracts upkeep.
  Stockpiles stop at zero; running out has no further penalty yet.
- Power is not stockpiled. Power plants (and the capital) supply it; most
  other buildings draw it. If demand exceeds supply, buildings that draw power
  produce proportionally less.
- Each bank adds 10% to money made by buildings, up to 50%.
- The resource bar shows the selected side's stockpile, next turn's change
  and power supply / demand.
- **Sandbox** ignores costs and training requirements (terrain rules still
  apply), for setting up test situations.

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
scripts/units/unit_types.gd    Unit type stats and which biomes each may occupy
scripts/units/unit_manager.gd  Units on the map, stacking and placement rules
scripts/units/unit_layer.gd    Unit tokens drawn on the globe
scripts/buildings/             Building types, manager and globe layer
scripts/economy/resource_types.gd  Resource definitions
scripts/combat/battle.gd       Battle rules
scripts/ui/                    Battle screen and slider
scripts/game_state.gd          Costs, training, power and per-turn income
scripts/world/planet_mesh.gd   Mesh and tile-colour texture builder
shaders/                       Tile, atmosphere and starfield shaders
tests/                         Headless tests
```

Each tile's colour lives in a lookup texture rather than in the mesh, so tiles
can be recoloured cheaply later (ownership, fog of war, and so on).

## Tests

```bash
godot --headless --path . --script res://tests/test_planet.gd
godot --headless --path . --script res://tests/test_units.gd
godot --headless --path . --script res://tests/test_buildings.gd
godot --headless --path . --script res://tests/test_combat.gd
godot --headless --path . --script res://tests/test_interaction.gd
```

## Debug options

Pass options after `--`, for example to generate a world straight away and save
a screenshot:

```bash
godot --path . -- --size=60 --seed=42 --autostart --view=20,0,18 --weather --turns=3 --screenshot=shot.png
```
