class_name RobotLoadout extends RefCounted
## A built robot: the four parts it was assembled from. Stats and looks derive from these.

var legs: ItemDef
var torso: ItemDef
var head: ItemDef
var arms: ItemDef

func signature() -> String:
	return "%s|%s|%s|%s" % [legs.id, torso.id, head.id, arms.id]
