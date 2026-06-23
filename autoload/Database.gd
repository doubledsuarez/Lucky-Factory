extends Node
## Holds all game content and looks it up by id.

# content is split by category so the files stay small; add a new file's preload here to register it
const CONTENT := [
	preload("res://data/content/items/materials.gd"),
	preload("res://data/content/items/scrap_parts.gd"),
	preload("res://data/content/machines/endpoints.gd"),
	preload("res://data/content/machines/fabricators.gd"),
	preload("res://data/content/tech_nodes.gd"),
]

var items: Dictionary = {}              # id -> ItemDef
var machines: Dictionary = {}           # id -> MachineDef
var tech_nodes: Dictionary = {}         # id -> TechNode

var _parts_by_slot: Dictionary = {}     # slot -> Array of ItemDef

func _ready() -> void:
	for content in CONTENT:
		content.register(self)
	_build_indexes()
	_build_tech_graph()

func add_item(definition: ItemDef) -> void:
	items[definition.id] = definition

func add_machine(definition: MachineDef) -> void:
	machines[definition.id] = definition

func add_tech_node(node: TechNode) -> void:
	tech_nodes[node.id] = node

func tech_node(id: StringName) -> TechNode:
	return tech_nodes.get(id)

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

# fill in each node's children and its left-to-right column from the parent links
func _build_tech_graph() -> void:
	for node in tech_nodes.values():
		for parent_id in node.parents:
			var parent: TechNode = tech_nodes.get(parent_id)
			if parent == null:
				push_warning("Tech node '%s' lists unknown parent '%s'" % [node.id, parent_id])
				continue
			parent.children.append(node.id)
	var depth_cache := {}
	for node in tech_nodes.values():
		node.column = _tech_column(node, depth_cache)

func _tech_column(node: TechNode, cache: Dictionary) -> int:
	if cache.has(node.id):
		return cache[node.id]
	var column := 0
	for parent_id in node.parents:
		var parent: TechNode = tech_nodes.get(parent_id)
		if parent != null:
			column = maxi(column, _tech_column(parent, cache) + 1)
	cache[node.id] = column
	return column
