class_name Players
extends RefCounted
## The players in the current game. Units, buildings and stockpiles refer to a
## player by index into `list`.

const MIN_PLAYERS := 2
const MAX_PLAYERS := 20

## Name and colour for each possible player, chosen to stay distinguishable.
const PALETTE := [
	["Blue", "3d8bfd"], ["Red", "e5484d"], ["Green", "46a758"], ["Yellow", "f5d90a"],
	["Purple", "8e4ec6"], ["Orange", "f76808"], ["Cyan", "05c4d8"], ["Pink", "e93d82"],
	["Lime", "99d52a"], ["Brown", "a0673c"], ["Teal", "12a594"], ["Violet", "b18cff"],
	["Gold", "c79a1e"], ["Crimson", "a8123e"], ["Sky", "8ecbff"], ["Olive", "7d8a2e"],
	["Magenta", "d23fd2"], ["Navy", "3a4fb8"], ["Coral", "ff8f7a"], ["Grey", "9aa1a9"],
]

## [{name: String, color: Color}]
static var list: Array[Dictionary] = _make(MIN_PLAYERS)


## Starts a game with this many players (clamped to MIN_PLAYERS..MAX_PLAYERS).
static func setup(player_count: int) -> void:
	list = _make(clampi(player_count, MIN_PLAYERS, MAX_PLAYERS))


static func count() -> int:
	return list.size()


static func _make(player_count: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in player_count:
		out.append({"name": PALETTE[i][0], "color": Color(PALETTE[i][1])})
	return out
