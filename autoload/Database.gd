extends Node
## Holds all game content and looks it up by id.

# content is split by category so the files stay small; add a new file's preload here to register it
const CONTENT := [
	preload("res://data/content/items/materials.gd"),
	preload("res://data/content/items/scrap_parts.gd"),
	preload("res://data/content/machines/endpoints.gd"),
	preload("res://data/content/machines/fabricators.gd"),
]

var items: Dictionary = {}              # id -> ItemDef
var machines: Dictionary = {}           # id -> MachineDef

var _parts_by_slot: Dictionary = {}     # slot -> Array of ItemDef

func _ready() -> void:
	for content in CONTENT:
		content.register(self)
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
