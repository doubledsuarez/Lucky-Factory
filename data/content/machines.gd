extends RefCounted
## Every machine in the game. Add new ones here.
## Ports are authored in the default orientation; sides are 0 right, 1 down, 2 left, 3 up.

const RIGHT := 0
const DOWN := 1
const LEFT := 2
const UP := 3
const INPUT := MachinePort.Role.INPUT
const OUTPUT := MachinePort.Role.OUTPUT

static func register(database) -> void:
	database.add_machine(_depo())
	database.add_machine(_shuttle())
	database.add_machine(_forge())
	database.add_machine(_crafter())
	database.add_machine(_assembler())
	database.add_machine(_bank())

static func _depo() -> MachineDef:
	var def := _machine(&"depo", "Depo", Color(0.35, 0.28, 0.18), MachineDef.Kind.SOURCE)
	def.source_item = &"scrap"
	def.ports = [_port(0, 0, RIGHT, OUTPUT)]
	return def

static func _shuttle() -> MachineDef:
	var def := _machine(&"shuttle", "Shuttle", Color(0.30, 0.35, 0.45), MachineDef.Kind.SHUTTLE)
	def.ports = [_port(0, 0, LEFT, INPUT)]
	return def

static func _forge() -> MachineDef:
	var def := _machine(&"forge", "Forge", Color(0.80, 0.45, 0.20), MachineDef.Kind.CRAFTER)
	def.build_cost = 25
	def.recipe = _recipe(&"scrap", 1, &"ingot", 1, 5.0)
	def.ports = [_port(0, 0, LEFT, INPUT), _port(0, 0, RIGHT, OUTPUT)]
	return def

static func _crafter() -> MachineDef:
	# 1 wide x 2 tall; item enters the bottom end, the part leaves the top end
	var def := _machine(&"crafter", "Crafter", Color(0.45, 0.55, 0.35), MachineDef.Kind.CRAFTER)
	def.build_cost = 25
	def.footprint = Vector2i(1, 2)
	def.recipes = [
		_recipe(&"ingot", 5, &"part_head", 1, 3.0),
		_recipe(&"ingot", 10, &"part_torso", 1, 6.0),
		_recipe(&"ingot", 5, &"part_arms", 1, 3.0),
		_recipe(&"ingot", 5, &"part_legs", 1, 3.0),
	]
	def.recipe = def.recipes[0]
	def.ports = [_port(0, 1, DOWN, INPUT), _port(0, 0, UP, OUTPUT)]
	return def

static func _assembler() -> MachineDef:
	# 4x4; four part inputs along the bottom, the finished robot leaves the back (top)
	var def := _machine(&"assembler", "Assembler", Color(0.55, 0.50, 0.75), MachineDef.Kind.ASSEMBLER)
	def.build_cost = 30
	def.footprint = Vector2i(4, 4)
	def.recipe = _robot_recipe()
	def.ports = [
		_port(0, 3, DOWN, INPUT),
		_port(1, 3, DOWN, INPUT),
		_port(2, 3, DOWN, INPUT),
		_port(3, 3, DOWN, INPUT),
		_port(1, 0, UP, OUTPUT),
	]
	return def

static func _bank() -> MachineDef:
	# 2x2; input and output sit next to each other on the bottom edge
	var def := _machine(&"bank", "Bank", Color(0.30, 0.45, 0.70), MachineDef.Kind.STORAGE)
	def.build_cost = 25
	def.footprint = Vector2i(2, 2)
	def.storage_item = &"ingot"
	def.storage_capacity = 100
	def.ports = [_port(0, 1, DOWN, INPUT), _port(1, 1, DOWN, OUTPUT)]
	return def

static func _machine(id: StringName, display_name: String, color: Color, kind: MachineDef.Kind) -> MachineDef:
	var def := MachineDef.new()
	def.id = id
	def.display_name = display_name
	def.color = color
	def.kind = kind
	return def

static func _port(x: int, y: int, side: int, role: MachinePort.Role) -> MachinePort:
	var port := MachinePort.new()
	port.cell = Vector2i(x, y)
	port.side = side
	port.role = role
	return port

static func _recipe(input_id: StringName, input_count: int, output_id: StringName, output_count: int, craft_time: float) -> Recipe:
	var recipe := Recipe.new()
	recipe.inputs = { input_id: input_count }
	recipe.output_id = output_id
	recipe.output_count = output_count
	recipe.craft_time = craft_time
	return recipe

static func _robot_recipe() -> Recipe:
	# the assembler builds from one of each part (handled in code), so no item inputs here
	var recipe := Recipe.new()
	recipe.output_id = &"robot"
	recipe.output_count = 1
	recipe.craft_time = 4.0
	return recipe
