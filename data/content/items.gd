extends RefCounted
## Every item in the game. Add new ones here.

static func register(database) -> void:
	database.add_item(_basic(&"scrap", "Scrap", Color(0.55, 0.40, 0.25), 20))
	database.add_item(_basic(&"ingot", "Scrap Ingot", Color(0.70, 0.72, 0.78), 10))
	database.add_item(_part(&"part_head", "Head", ItemDef.Slot.HEAD, Color(0.75, 0.75, 0.82)))
	database.add_item(_part(&"part_torso", "Torso", ItemDef.Slot.TORSO, Color(0.40, 0.55, 0.85)))
	database.add_item(_part(&"part_arms", "Arms", ItemDef.Slot.ARMS, Color(0.85, 0.75, 0.35)))
	database.add_item(_part(&"part_legs", "Legs", ItemDef.Slot.LEGS, Color(0.45, 0.45, 0.52)))

static func _basic(id: StringName, display_name: String, color: Color, stack_size: int) -> ItemDef:
	var definition := ItemDef.new()
	definition.id = id
	definition.display_name = display_name
	definition.color = color
	definition.stack_size = stack_size
	return definition

static func _part(id: StringName, display_name: String, slot: ItemDef.Slot, color: Color) -> ItemDef:
	var definition := _basic(id, display_name, color, 1)
	definition.slot = slot
	return definition
