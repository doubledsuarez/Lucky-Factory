class_name ItemBuilders extends RefCounted
## Shared helpers for authoring items. The scrap family shares one color; the shape tells them apart.

const SCRAP_COLOR := Color(0.62, 0.45, 0.28)

static func make(id: StringName, display_name: String, shape: ItemDef.Shape, stack_size: int) -> ItemDef:
	var definition := ItemDef.new()
	definition.id = id
	definition.display_name = display_name
	definition.color = SCRAP_COLOR
	definition.shape = shape
	definition.stack_size = stack_size
	return definition

static func part(id: StringName, display_name: String, slot: ItemDef.Slot, shape: ItemDef.Shape) -> ItemDef:
	var definition := make(id, display_name, shape, 1)
	definition.slot = slot
	return definition

static func head(id: StringName, display_name: String, armor: int) -> ItemDef:
	var definition := part(id, display_name, ItemDef.Slot.HEAD, ItemDef.Shape.CIRCLE)
	definition.armor = armor
	return definition

static func torso(id: StringName, display_name: String, armor: int, turn_rate: float, speed: float, shield: int = 0) -> ItemDef:
	var definition := part(id, display_name, ItemDef.Slot.TORSO, ItemDef.Shape.HEXAGON)
	definition.armor = armor
	definition.turn_rate = turn_rate
	definition.speed = speed
	definition.shield = shield
	return definition

static func legs(id: StringName, display_name: String, armor: int, speed: float) -> ItemDef:
	var definition := part(id, display_name, ItemDef.Slot.LEGS, ItemDef.Shape.DIAMOND)
	definition.armor = armor
	definition.speed = speed
	return definition

static func arms(id: StringName, display_name: String, armor: int, damage: int, attack_range: float, attack_speed: float) -> ItemDef:
	var definition := part(id, display_name, ItemDef.Slot.ARMS, ItemDef.Shape.TRIANGLE)
	definition.armor = armor
	definition.damage = damage
	definition.attack_range = attack_range
	definition.attack_speed = attack_speed
	return definition
