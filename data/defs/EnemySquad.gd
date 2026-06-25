class_name EnemySquad extends RefCounted
## A group of identical enemy robots in a wave: the four part ids, and how many of them.
## Enemies are built from the same parts the player uses (boss parts can be added later).

var legs: StringName
var torso: StringName
var head: StringName
var arms: StringName
var count: int = 1

# build one enemy robot from this squad's parts
func to_loadout() -> RobotLoadout:
	var loadout := RobotLoadout.new()
	loadout.legs = Database.item(legs)
	loadout.torso = Database.item(torso)
	loadout.head = Database.item(head)
	loadout.arms = Database.item(arms)
	return loadout
