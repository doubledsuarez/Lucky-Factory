extends RefCounted
## Raw materials and the finished robot.

static func register(database) -> void:
	database.add_item(ItemBuilders.make(&"scrap", "Scrap", ItemDef.Shape.SQUARE, 20))
	database.add_item(ItemBuilders.make(&"ingot", "Scrap Ingot", ItemDef.Shape.TRAPEZOID, 10))
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
