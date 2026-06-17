extends Node
## Holds all game content and looks it up by id.

const ITEM_CONTENT := preload("res://data/content/items.gd")
const MACHINE_CONTENT := preload("res://data/content/machines.gd")

var items: Dictionary = {}              # id -> ItemDef
var machines: Dictionary = {}           # id -> MachineDef

var _parts_by_slot: Dictionary = {}     # slot -> Array of ItemDef

func _ready() -> void:
	ITEM_CONTENT.register(self)
	MACHINE_CONTENT.register(self)
	_build_indexes()

func add_item(definition: ItemDef) -> void:
	items[definition.id] = definition

func add_machine(definition: MachineDef) -> void:
	machines[definition.id] = definition

func item(id: StringName) -> ItemDef:
	return items.get(id)

func machine(id: StringName) -> MachineDef:
	return machines.get(id)

func parts_by_slot(slot: int) -> Array:
	return _parts_by_slot.get(slot, [])

func items_by_tier(tier: int) -> Array:
	var result := []
	for definition in items.values():
		if definition.tier == tier:
			result.append(definition)
	return result

func _build_indexes() -> void:
	_parts_by_slot.clear()
	for definition in items.values():
		if definition.slot == ItemDef.Slot.NONE:
			continue
		if not _parts_by_slot.has(definition.slot):
			_parts_by_slot[definition.slot] = []
		_parts_by_slot[definition.slot].append(definition)
