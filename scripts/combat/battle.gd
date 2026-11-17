class_name Battle
extends RefCounted
## One battle for a tile.
##
## The slider runs from 0 to Total = attacker power + defender power. The
## attacker owns 0..attacker power and the defender owns the rest. Each round a
## roll is drawn from a normal distribution centred on Total / 2 with a standard
## deviation of SPREAD x Total, clamped to the slider. The side whose zone the
## roll lands in deals damage to the other side equal to the distance from the
## roll to the dividing line.
##
## Sequence (see `phase`):
##   COMMIT   attacker picks units from one adjacent tile (plus air / naval
##            support), then the defender picks; defenders left out retreat.
##            Air defense, coastal batteries and artillery then fire for free.
##   ROLL     roll_round()
##   ASSIGN   the damaged side assigns damage with assign() / auto_assign()
##   RETREAT  both sides choose units to pull out, revealed together:
##            submit_retreat(). Retreating units take a pursuit hit.
##   ...back to ROLL until only one side is left: FINISHED.
##
## A unit's power is its remaining hit points times its modifiers, so damaged
## units fight at reduced power.

enum Phase { COMMIT, ROLL, ASSIGN, RETREAT, FINISHED }

const ATTACKER := 0
const DEFENDER := 1

## Standard deviation of the roll as a share of Total. The luck knob.
const SPREAD := 0.15
## Base multiplier on the defending side's power.
const DEFENDER_MULTIPLIER := 1.2
## Extra defender multiplier in a city.
const CITY_DEFENDER_BONUS := 0.2
## Units out of supply fight at this share of their power.
const UNSUPPLIED_MULTIPLIER := 0.5
## Retreating units take this share of the remaining enemy power as damage.
const PURSUIT_SHARE := 0.25

var game: GameState
var planet: Planet
var weather: WeatherSystem
var rng: RandomNumberGenerator

var tile := -1        ## the tile being fought over
var from_tile := -1   ## the tile the attacker's ground units come from
## Side (index into UnitManager.PLAYERS) of the attacker and the defender.
var sides: Array[int] = [0, 1]

var phase := Phase.COMMIT
var round_number := 0
## Units still fighting, per side.
var committed: Array[Array] = [[], []]
## Winner (ATTACKER / DEFENDER) once FINISHED, else -1.
var winner := -1
## Damage waiting to be assigned: [{side, amount, pool: Array[Unit], reason}].
var pending: Array[Dictionary] = []
## The last roll: {total, line, roll, hit_side, damage}.
var last_roll := {}
## What has happened so far, one line per event.
var events: Array[String] = []

var _in_city := false
var _remote := {}          # Unit -> true: supporting from elsewhere
var _supplied := {}        # Unit -> bool
var _near := {}            # radius -> tiles_within(tile, radius)
var _after_pending := Callable()
var _retreating: Array[Array] = [[], []]


func _init(game_state: GameState, attacker_side: int, attack_from: int, target: int,
		weather_system: WeatherSystem = null, random: RandomNumberGenerator = null) -> void:
	game = game_state
	planet = game.planet
	weather = weather_system
	rng = random if random != null else RandomNumberGenerator.new()
	tile = target
	from_tile = attack_from
	sides[ATTACKER] = attacker_side
	sides[DEFENDER] = _find_defender_side(attacker_side)
	_in_city = game.is_city(tile)


## Empty if this side may attack `target` from `attack_from`, otherwise why not.
static func start_block_reason(game_state: GameState, attacker_side: int,
		attack_from: int, target: int) -> String:
	if attack_from < 0 or target < 0:
		return "Select one of your tiles, then an adjacent enemy tile"
	if not game_state.planet.get_neighbors(attack_from).has(target):
		return "The target must be next to the attacking tile"
	var has_enemy := false
	for unit in game_state.units.units_at(target):
		if unit.owner != attacker_side:
			has_enemy = true
	if not has_enemy:
		return "There are no enemy units on that tile"
	var can_reach := false
	for unit in game_state.units.units_at(attack_from):
		if unit.owner == attacker_side and game_state.units.can_place(unit.type, target) \
				and unit.data()["support"] != UnitTypes.Support.AIRBASE:
			can_reach = true
	if not can_reach:
		return "None of your units there can attack that tile"
	return ""


func side_name(side: int) -> String:
	return UnitManager.PLAYERS[sides[side]]["name"]


# --- Who can fight ---------------------------------------------------------------

## Units a side may commit. For the attacker: its units on `from_tile` that can
## enter the tile. For the defender: its units on the tile. Both also get air
## support from airbases in range and, for land battles, naval bombardment.
func candidates(side: int) -> Array[Unit]:
	var owner := sides[side]
	var out: Array[Unit] = []
	var home := from_tile if side == ATTACKER else tile
	for unit in game.units.units_at(home):
		if unit.owner != owner:
			continue
		if side == ATTACKER and (not game.units.can_place(unit.type, tile)
				or unit.data()["support"] == UnitTypes.Support.AIRBASE):
			continue
		out.append(unit)
	for unit in _support_candidates(owner):
		if not out.has(unit):
			out.append(unit)
	return out


## True if the unit is (or would be) supporting from another tile.
func is_remote(unit: Unit) -> bool:
	if _remote.has(unit):
		return true
	var data := unit.data()
	if data["support"] == UnitTypes.Support.AIRBASE:
		return unit.tile != tile
	if data["support"] == UnitTypes.Support.BOMBARD:
		return not Biomes.is_water(planet.biomes[tile])
	return false


func _support_candidates(owner: int) -> Array[Unit]:
	var out: Array[Unit] = []
	var conditions := Weather.info(weather.weather_at(tile)) if weather != null else {}
	var land_battle := not Biomes.is_water(planet.biomes[tile])
	for unit in game.units.units:
		if unit.owner != owner or unit.tile == tile:
			continue
		var data := unit.data()
		match data["support"]:
			UnitTypes.Support.AIRBASE:
				if not conditions.get("air_support", true):
					continue
				for building in game.buildings.buildings_at(unit.tile):
					var reach: int = building.data()["effects"].get("aircraft_operating_range", -1)
					if building.owner == owner and reach >= 0 \
							and _within(reach).has(unit.tile):
						out.append(unit)
						break
			UnitTypes.Support.BOMBARD:
				if land_battle and conditions.get("offboard_support", true) \
						and _within(data["bombard_range"]).has(unit.tile):
					out.append(unit)
	return out


## Tiles within `radius` of the battle tile (cached).
func _within(radius: int) -> Dictionary:
	if not _near.has(radius):
		_near[radius] = planet.tiles_within(tile, radius)
	return _near[radius]


func _find_defender_side(attacker_side: int) -> int:
	for unit in game.units.units_at(tile):
		if unit.owner != attacker_side:
			return unit.owner
	return (attacker_side + 1) % UnitManager.PLAYERS.size()


# --- Power -----------------------------------------------------------------------

## A unit's power in this battle: hit points x terrain x role x supply.
func unit_power(unit: Unit, side: int) -> float:
	var data := unit.data()
	var power := float(unit.hit_points)
	if data["domain"] == UnitTypes.Domain.LAND:
		power *= UnitTypes.terrain_multiplier(unit.type, planet.biomes[tile], _in_city)
	if side == DEFENDER:
		power *= data["defending_multiplier"]
	if not is_supplied(unit):
		power *= UNSUPPLIED_MULTIPLIER
	return power


func is_supplied(unit: Unit) -> bool:
	if not _supplied.has(unit):
		_supplied[unit] = game.is_supplied(unit)
	return _supplied[unit]


## Multiplier on the defending side's total: base, fortifications, city.
func defender_multiplier() -> float:
	var multiplier := DEFENDER_MULTIPLIER
	if _in_city:
		multiplier += CITY_DEFENDER_BONUS
	for building in game.buildings.buildings_at(tile):
		if building.owner == sides[DEFENDER]:
			multiplier += building.data()["effects"].get("defender_multiplier_bonus", 0.0)
	return multiplier


## Total power of a side's listed units (default: those still committed).
func side_power(side: int, units: Array = []) -> float:
	var total := 0.0
	for unit: Unit in (units if not units.is_empty() else committed[side]):
		total += unit_power(unit, side)
	if side == DEFENDER:
		total *= defender_multiplier()
	return total


# --- Commit ----------------------------------------------------------------------

## Both sides' choices. Defenders on the tile that are left out retreat to an
## adjacent safe tile, or are lost if there is none. Then free fire happens.
func commit(attackers: Array, defenders: Array) -> void:
	assert(phase == Phase.COMMIT)
	var allowed := [candidates(ATTACKER), candidates(DEFENDER)]
	committed[ATTACKER] = attackers.filter(func(u: Unit) -> bool: return allowed[ATTACKER].has(u))
	committed[DEFENDER] = defenders.filter(func(u: Unit) -> bool: return allowed[DEFENDER].has(u))
	for side in 2:
		for unit: Unit in committed[side]:
			if is_remote(unit):
				_remote[unit] = true
	events.append("%s attacks %s with %d unit(s); %s defends with %d." % [
		side_name(ATTACKER), Biomes.display_name(planet.biomes[tile]),
		committed[ATTACKER].size(), side_name(DEFENDER), committed[DEFENDER].size()])
	if defender_multiplier() != 1.0:
		events.append("Defender multiplier x%.2f%s." % [defender_multiplier(), " (city)" if _in_city else ""])

	for unit in game.units.units_at(tile).duplicate():
		if unit.owner == sides[DEFENDER] and not committed[DEFENDER].has(unit):
			_withdraw(unit)

	if committed[ATTACKER].is_empty() or committed[DEFENDER].is_empty():
		_check_end()
		return
	_queue_free_fire()
	_resolve_pending(func() -> void:
		if not _check_end():
			phase = Phase.ROLL)


## Air defense and coastal batteries hit supporting aircraft and ships first;
## artillery fires a free round. All of it is worked out before any is applied.
func _queue_free_fire() -> void:
	for side in 2:
		var enemy := 1 - side
		# Interceptors owned by `side` near the battle.
		var site_power := {}  # intercepted unit type -> power
		for t: int in _within(4):
			for building in game.buildings.buildings_at(t):
				var effects: Dictionary = building.data()["effects"]
				if building.owner == sides[side] and effects.has("intercepts") \
						and _within(effects["range"]).has(t):
					site_power[effects["intercepts"]] = site_power.get(effects["intercepts"], 0) + effects["power"]
		for unit_type: int in site_power:
			var targets: Array = committed[enemy].filter(
				func(u: Unit) -> bool: return u.type == unit_type and _remote.has(u))
			var damage := _free_roll(site_power[unit_type])
			if not targets.is_empty() and damage > 0:
				pending.append({"side": enemy, "amount": damage, "pool": targets,
					"reason": "%s's defenses fire on incoming %s" % [
						side_name(side), UnitTypes.display_name(unit_type).to_lower()]})

		var guns := 0.0
		for unit: Unit in committed[side]:
			if unit.data()["pre_battle_fire"]:
				guns += unit_power(unit, side)
		var barrage := _free_roll(guns)
		if barrage > 0:
			pending.append({"side": enemy, "amount": barrage, "pool": committed[enemy],
				"reason": "%s's artillery opens fire" % side_name(side)})


## Unopposed fire: the same bell curve on a slider of the firer's own power.
func _free_roll(power: float) -> int:
	if power <= 0.0:
		return 0
	return roundi(clampf(rng.randfn(power / 2.0, SPREAD * power), 0.0, power))


# --- Rounds ----------------------------------------------------------------------

## Rolls one round and queues the damage for the losing side to assign.
func roll_round() -> void:
	assert(phase == Phase.ROLL)
	round_number += 1
	var attack := side_power(ATTACKER)
	var defense := side_power(DEFENDER)
	var total := attack + defense
	var roll := clampf(rng.randfn(total / 2.0, SPREAD * total), 0.0, total)
	var hit_side := DEFENDER if roll < attack else ATTACKER
	var damage := roundi(absf(attack - roll))
	last_roll = {"total": total, "line": attack, "roll": roll, "hit_side": hit_side, "damage": damage}
	if damage > 0:
		pending.append({"side": hit_side, "amount": damage, "pool": committed[hit_side],
			"reason": "Round %d: rolled %.1f on 0-%.1f (line at %.1f)" % [round_number, roll, total, attack]})
	else:
		events.append("Round %d: rolled %.1f, right on the line. No damage." % [round_number, roll])
	_resolve_pending(func() -> void:
		if not _check_end():
			phase = Phase.RETREAT)


# --- Damage ------------------------------------------------------------------------

## The damage the current side must assign, or {} if none.
func current_damage() -> Dictionary:
	return pending[0] if not pending.is_empty() else {}


## Units that can take the current damage.
func damage_pool() -> Array:
	if pending.is_empty():
		return []
	return pending[0]["pool"].filter(func(u: Unit) -> bool: return u.hit_points > 0)


## The damaged side puts the current damage on a unit. The unit absorbs as much
## as it can; anything left over must go on another unit.
func assign(unit: Unit) -> void:
	if pending.is_empty() or not damage_pool().has(unit):
		return
	var entry: Dictionary = pending[0]
	var dealt := mini(entry["amount"], unit.hit_points)
	unit.hit_points -= dealt
	entry["amount"] -= dealt
	if unit.hit_points <= 0:
		events.append("  %s's %s takes %d and is destroyed." % [side_name(entry["side"]), unit.display_name(), dealt])
		_destroy(unit)
	else:
		events.append("  %s's %s takes %d (%d left)." % [
			side_name(entry["side"]), unit.display_name(), dealt, unit.hit_points])
		game.units.changed.emit()
	if entry["amount"] <= 0 or damage_pool().is_empty():
		pending.pop_front()
		_resolve_pending(_after_pending)


## Assigns all waiting damage for the side, cheapest units first.
func auto_assign() -> void:
	while phase == Phase.ASSIGN and not pending.is_empty():
		var pool := damage_pool()
		pool.sort_custom(func(a: Unit, b: Unit) -> bool:
			var cost_a: int = a.data()["cost"].get(ResourceTypes.Type.MONEY, 0)
			var cost_b: int = b.data()["cost"].get(ResourceTypes.Type.MONEY, 0)
			return cost_a < cost_b if cost_a != cost_b else a.hit_points < b.hit_points)
		assign(pool[0])


func _resolve_pending(then: Callable) -> void:
	_after_pending = then
	while not pending.is_empty() and damage_pool().is_empty():
		pending.pop_front()
	if pending.is_empty():
		_after_pending = Callable()
		if then.is_valid():
			then.call()
		return
	var entry: Dictionary = pending[0]
	if not entry.get("announced", false):
		entry["announced"] = true
		events.append("%s. %s takes %d damage." % [entry["reason"], side_name(entry["side"]), entry["amount"]])
	phase = Phase.ASSIGN


func _destroy(unit: Unit) -> void:
	for side in 2:
		committed[side].erase(unit)
		_retreating[side].erase(unit)
	game.units.remove_unit(unit)


# --- Retreat -----------------------------------------------------------------------

## Both sides' retreat choices, revealed together. Units physically in the
## fight take a pursuit hit from the enemy that stays; supporting aircraft and
## ships simply break off.
func submit_retreat(attackers: Array, defenders: Array) -> void:
	assert(phase == Phase.RETREAT)
	var choices := [attackers, defenders]
	for side in 2:
		_retreating[side] = choices[side].filter(func(u: Unit) -> bool: return committed[side].has(u))
		for unit: Unit in _retreating[side]:
			committed[side].erase(unit)
	for side in 2:
		if _retreating[side].is_empty():
			continue
		events.append("%s pulls out %d unit(s)." % [side_name(side), _retreating[side].size()])
		var chased: Array = _retreating[side].filter(func(u: Unit) -> bool: return not _remote.has(u))
		var enemy := 1 - side
		var pursuit := roundi(PURSUIT_SHARE * side_power(enemy)) if not committed[enemy].is_empty() else 0
		if pursuit > 0 and not chased.is_empty():
			pending.append({"side": side, "amount": pursuit, "pool": chased,
				"reason": "%s pursues the retreat" % side_name(enemy)})
	_resolve_pending(func() -> void:
		for unit: Unit in _retreating[DEFENDER].duplicate():
			if not _remote.has(unit):
				_withdraw(unit)
		_retreating = [[], []]
		if not _check_end():
			phase = Phase.ROLL)


## Moves a defender off the tile to an adjacent safe tile: one it can occupy,
## with no enemy units or buildings. Prefers friendly ground. Lost if none.
func _withdraw(unit: Unit) -> void:
	var best := -1
	var best_score := -1
	for nb in planet.get_neighbors(tile):
		if not game.units.can_place(unit.type, nb):
			continue
		var owner := game.buildings.owner_of(nb)
		if owner >= 0 and owner != unit.owner:
			continue
		var stack := game.units.units_at(nb)
		if stack.any(func(u: Unit) -> bool: return u.owner != unit.owner):
			continue
		var score := (2 if owner == unit.owner else 0) + (1 if not stack.is_empty() else 0)
		if score > best_score:
			best_score = score
			best = nb
	if best >= 0:
		game.units.relocate(unit, best)
		events.append("  %s's %s falls back." % [side_name(DEFENDER), unit.display_name()])
	else:
		events.append("  %s's %s has nowhere to go and is lost." % [side_name(DEFENDER), unit.display_name()])
		_destroy(unit)


# --- Ending ------------------------------------------------------------------------

func _check_end() -> bool:
	if not committed[ATTACKER].is_empty() and not committed[DEFENDER].is_empty():
		return false
	phase = Phase.FINISHED
	if committed[ATTACKER].is_empty():
		winner = DEFENDER
		events.append("%s holds the tile." % side_name(DEFENDER))
		return true
	winner = ATTACKER
	var holders := 0
	for unit: Unit in committed[ATTACKER]:
		if not _remote.has(unit) and game.units.relocate(unit, tile):
			if unit.data()["can_hold_territory"]:
				holders += 1
	if holders > 0:
		events.append("%s takes the tile." % side_name(ATTACKER))
		if game.buildings.owner_of(tile) == sides[DEFENDER]:
			game.buildings.capture_tile(tile, sides[ATTACKER])
			events.append("%s captures the buildings there." % side_name(ATTACKER))
	else:
		events.append("%s wins the battle but has nothing there to hold the tile." % side_name(ATTACKER))
	return true


# --- Simulation --------------------------------------------------------------------

## Plays out a battle between two bare power totals with no retreats, applying
## the slider rule until one side reaches zero. Returns {attacker_won, rounds}.
static func simulate(attack: float, defense: float, spread: float,
		random: RandomNumberGenerator) -> Dictionary:
	var rounds := 0
	while attack > 0.0 and defense > 0.0:
		rounds += 1
		var total := attack + defense
		var roll := clampf(random.randfn(total / 2.0, spread * total), 0.0, total)
		var damage := float(roundi(absf(attack - roll)))
		if roll < attack:
			defense -= damage
		else:
			attack -= damage
	return {"attacker_won": attack > 0.0, "rounds": rounds}
