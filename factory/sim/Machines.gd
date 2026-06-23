class_name Machines extends RefCounted
## What each machine does per tick: sources emit, crafters and assemblers build, storage dispenses.
## The grid plumbing (pushing output onto a belt) lives on Factory; this is just the behavior.

static func tick(factory: Factory, scaled_delta: float) -> void:
	for coordinate in factory.cells.keys():
		var cell: Cell = factory.cells[coordinate]
		if cell.kind != Factory.CellKind.MACHINE or cell.machine_origin != coordinate:
			continue  # tick each machine once, at its origin cell
		match cell.machine.definition.kind:
			MachineDef.Kind.SOURCE: tick_source(factory, cell)
			MachineDef.Kind.CRAFTER: tick_crafter(factory, cell, scaled_delta)
			MachineDef.Kind.ASSEMBLER: tick_assembler(factory, cell, scaled_delta)
			MachineDef.Kind.STORAGE: tick_storage(factory, cell)

static func tick_source(factory: Factory, cell: Cell) -> void:
	var machine := cell.machine
	if machine.stored <= 0:
		return
	if factory._push_machine_output(machine, Database.item(machine.definition.source_item)):
		machine.stored -= 1

static func tick_crafter(factory: Factory, cell: Cell, scaled_delta: float) -> void:
	var machine := cell.machine
	var recipe := machine.recipe
	if recipe == null:
		return  # waiting on a recipe to be picked
	var output_definition := Database.item(recipe.output_id)
	if machine.output_count < output_definition.stack_size and has_recipe_inputs(machine, recipe):
		machine.progress += scaled_delta
		if machine.progress >= recipe.craft_time:
			machine.progress = 0.0
			consume_recipe_inputs(machine, recipe)
			machine.output_item = output_definition
			machine.output_count += recipe.output_count
	if machine.output_count > 0 and factory._push_machine_output(machine, machine.output_item):
		machine.output_count -= 1

static func tick_storage(factory: Factory, cell: Cell) -> void:
	# the storage dispenses from the shared build reserve
	if factory.build_ingots <= 0:
		return
	if factory._push_machine_output(cell.machine, Database.item(cell.machine.definition.storage_item)):
		factory.build_ingots -= 1

static func tick_assembler(factory: Factory, cell: Cell, scaled_delta: float) -> void:
	var machine := cell.machine
	if machine.output_count == 0 and assembler_ready(machine):
		machine.progress += scaled_delta
		if machine.progress >= machine.recipe.craft_time:
			machine.progress = 0.0
			machine.output_loadout = build_loadout(machine)
			machine.output_count = 1
			machine.inputs.clear()
	if machine.output_count > 0 and factory._push_machine_output(machine, Database.item(&"robot"), machine.output_loadout):
		machine.output_count -= 1
		machine.output_loadout = null

static func assembler_ready(machine: Machine) -> bool:
	return machine.inputs.has(ItemDef.Slot.LEGS) and machine.inputs.has(ItemDef.Slot.TORSO) \
		and machine.inputs.has(ItemDef.Slot.HEAD) and machine.inputs.has(ItemDef.Slot.ARMS)

static func build_loadout(machine: Machine) -> RobotLoadout:
	var loadout := RobotLoadout.new()
	loadout.legs = machine.inputs[ItemDef.Slot.LEGS]
	loadout.torso = machine.inputs[ItemDef.Slot.TORSO]
	loadout.head = machine.inputs[ItemDef.Slot.HEAD]
	loadout.arms = machine.inputs[ItemDef.Slot.ARMS]
	return loadout

static func has_recipe_inputs(machine: Machine, recipe: Recipe) -> bool:
	for input_id in recipe.inputs:
		if machine.inputs.get(input_id, 0) < recipe.inputs[input_id]:
			return false
	return true

static func consume_recipe_inputs(machine: Machine, recipe: Recipe) -> void:
	for input_id in recipe.inputs:
		machine.inputs[input_id] -= recipe.inputs[input_id]
