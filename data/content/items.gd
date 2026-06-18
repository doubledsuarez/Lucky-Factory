extends RefCounted
## Every item in the game. Add new ones here.
## Everything in the scrap family shares one color; the shape is what tells them apart.

const SCRAP_COLOR := Color(0.62, 0.45, 0.28)

static func register(database) -> void:
	database.add_item(_make(&"scrap", "Scrap", ItemDef.Shape.SQUARE, 20))
	database.add_item(_make(&"ingot", "Scrap Ingot", ItemDef.Shape.TRAPEZOID, 10))
	database.add_item(_part(&"part_head", "Head", ItemDef.Slot.HEAD, ItemDef.Shape.CIRCLE))
	database.add_item(_part(&"part_torso", "Torso", ItemDef.Slot.TORSO, ItemDef.Shape.HEXAGON))
	database.add_item(_part(&"part_arms", "Arms", ItemDef.Slot.ARMS, ItemDef.Shape.TRIANGLE))
	database.add_item(_part(&"part_legs", "Legs", ItemDef.Slot.LEGS, ItemDef.Shape.DIAMOND))
	database.add_item(_robot())

static func _robot() -> ItemDef:
	# the finished robot, so it reads as its own thing rather than scrap
	var definition := ItemDef.new()
	definition.id = &"robot"
	definition.display_name = "Robot"
	definition.color = Color(0.55, 0.75, 0.95)
	definition.shape = ItemDef.Shape.SQUARE
	definition.stack_size = 1
	return definition

static func _make(id: StringName, display_name: String, shape: ItemDef.Shape, stack_size: int) -> ItemDef:
	var definition := ItemDef.new()
	definition.id = id
	definition.display_name = display_name
	definition.color = SCRAP_COLOR
	definition.shape = shape
	definition.stack_size = stack_size
	return definition

static func _part(id: StringName, display_name: String, slot: ItemDef.Slot, shape: ItemDef.Shape) -> ItemDef:
	var definition := _make(id, display_name, shape, 1)
	definition.slot = slot
	return definition
