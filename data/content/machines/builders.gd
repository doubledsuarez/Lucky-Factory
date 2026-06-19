class_name MachineBuilders extends RefCounted
## Shared helpers for authoring machines.
## Ports are authored in the default orientation; sides are 0 right, 1 down, 2 left, 3 up.

const RIGHT := 0
const DOWN := 1
const LEFT := 2
const UP := 3
const INPUT := MachinePort.Role.INPUT
const OUTPUT := MachinePort.Role.OUTPUT

static func machine(id: StringName, display_name: String, color: Color, kind: MachineDef.Kind) -> MachineDef:
	var def := MachineDef.new()
	def.id = id
	def.display_name = display_name
	def.color = color
	def.kind = kind
	return def

static func port(x: int, y: int, side: int, role: MachinePort.Role) -> MachinePort:
	var machine_port := MachinePort.new()
	machine_port.cell = Vector2i(x, y)
	machine_port.side = side
	machine_port.role = role
	return machine_port

static func recipe(input_id: StringName, input_count: int, output_id: StringName, output_count: int, craft_time: float) -> Recipe:
	var made := Recipe.new()
	made.inputs = { input_id: input_count }
	made.output_id = output_id
	made.output_count = output_count
	made.craft_time = craft_time
	return made

static func robot_recipe() -> Recipe:
	# the assembler builds from one of each part (handled in code), so no item inputs here
	var made := Recipe.new()
	made.output_id = &"robot"
	made.output_count = 1
	made.craft_time = 4.0
	return made
