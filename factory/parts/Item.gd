class_name Item extends RefCounted
## A single thing riding the belts: scrap, an ingot, a part, or a finished robot.

var definition: ItemDef
var offset: float = 0.0  # 0 at the input edge, 1 at the output edge
var loadout: RobotLoadout = null   # set on assembled-robot items
var route_entry: int = 0           # router transit: side it came in
var route_exit: int = -1           # router transit: side it's leaving (-1 = not chosen yet)

func _init(item_definition: ItemDef) -> void:
	definition = item_definition
