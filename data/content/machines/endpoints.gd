extends RefCounted
## Source, portals, and storage -- where materials enter, leave, and bank.

const RIGHT := MachineBuilders.RIGHT
const DOWN := MachineBuilders.DOWN
const LEFT := MachineBuilders.LEFT
const INPUT := MachineBuilders.INPUT
const OUTPUT := MachineBuilders.OUTPUT

# portal color -> display tint, in unlock order (blue starts active, the rest unlock via the tree)
const PORTALS := {
	&"blue": Color(0.25, 0.45, 0.85),
	&"green": Color(0.30, 0.70, 0.40),
	&"red": Color(0.80, 0.30, 0.30),
	&"orange": Color(0.90, 0.55, 0.20),
	&"yellow": Color(0.90, 0.80, 0.25),
}

static func register(database) -> void:
	database.add_machine(_scrap_depo())
	database.add_machine(_storage())
	for color in PORTALS:
		database.add_machine(_portal(color, PORTALS[color]))

static func _scrap_depo() -> MachineDef:
	# 2x2; two outputs down the right edge so the player can run two scrap lines
	var def := MachineBuilders.machine(&"scrap_depo", "Scrap Depo", Color(0.35, 0.28, 0.18), MachineDef.Kind.SOURCE)
	def.source_item = &"scrap"
	def.footprint = Vector2i(2, 2)
	def.ports = [MachineBuilders.port(1, 0, RIGHT, OUTPUT), MachineBuilders.port(1, 1, RIGHT, OUTPUT)]
	return def

static func _portal(color: StringName, tint: Color) -> MachineDef:
	# 2x2; robots enter on either cell of the left edge. Each portal feeds its own manifest.
	var name := String(color).capitalize() + " Portal"
	var def := MachineBuilders.machine(StringName("portal_" + color), name, tint, MachineDef.Kind.PORTAL)
	def.footprint = Vector2i(2, 2)
	def.portal_color = color
	def.ports = [MachineBuilders.port(0, 0, LEFT, INPUT), MachineBuilders.port(0, 1, LEFT, INPUT)]
	return def

static func _storage() -> MachineDef:
	# 2x2; input and output sit next to each other on the bottom edge
	var def := MachineBuilders.machine(&"storage", "Storage", Color(0.30, 0.45, 0.70), MachineDef.Kind.STORAGE)
	def.build_cost = 25
	def.footprint = Vector2i(2, 2)
	def.storage_item = &"scrap_ingot"
	def.storage_capacity = 100
	def.ports = [MachineBuilders.port(0, 1, DOWN, INPUT), MachineBuilders.port(1, 1, DOWN, OUTPUT)]
	return def
