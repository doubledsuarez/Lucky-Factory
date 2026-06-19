extends RefCounted
## Source, shuttle, and storage -- where materials enter, leave, and bank.

const RIGHT := MachineBuilders.RIGHT
const DOWN := MachineBuilders.DOWN
const LEFT := MachineBuilders.LEFT
const INPUT := MachineBuilders.INPUT
const OUTPUT := MachineBuilders.OUTPUT

static func register(database) -> void:
	database.add_machine(_depo())
	database.add_machine(_shuttle())
	database.add_machine(_bank())

static func _depo() -> MachineDef:
	var def := MachineBuilders.machine(&"depo", "Depo", Color(0.35, 0.28, 0.18), MachineDef.Kind.SOURCE)
	def.source_item = &"scrap"
	def.ports = [MachineBuilders.port(0, 0, RIGHT, OUTPUT)]
	return def

static func _shuttle() -> MachineDef:
	var def := MachineBuilders.machine(&"shuttle", "Shuttle", Color(0.30, 0.35, 0.45), MachineDef.Kind.SHUTTLE)
	def.ports = [MachineBuilders.port(0, 0, LEFT, INPUT)]
	return def

static func _bank() -> MachineDef:
	# 2x2; input and output sit next to each other on the bottom edge
	var def := MachineBuilders.machine(&"bank", "Bank", Color(0.30, 0.45, 0.70), MachineDef.Kind.STORAGE)
	def.build_cost = 25
	def.footprint = Vector2i(2, 2)
	def.storage_item = &"ingot"
	def.storage_capacity = 100
	def.ports = [MachineBuilders.port(0, 1, DOWN, INPUT), MachineBuilders.port(1, 1, DOWN, OUTPUT)]
	return def
