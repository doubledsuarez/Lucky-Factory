class_name FactorySave extends RefCounted
## Turns the whole factory floor into a plain dictionary and back -- the full mid-round snapshot.

static func capture_state(factory: Factory) -> Dictionary:
	var data := {
		"name": GameManager.current_save_name,
		"wave": factory.current_wave,
		"played_seconds": factory.played_seconds,
		"build_ingots": factory.build_ingots,
		"build_time_left": factory.build_time_left,
		"speed": Sim.speed,
		"unlocks": Unlocks.to_list(),
		"shuttle_robots": [],
		"cells": [],
	}
	for loadout in Run.shuttle_robots:
		data["shuttle_robots"].append(capture_loadout(loadout))
	for coordinate in factory.cells:
		var cell: Cell = factory.cells[coordinate]
		if cell.kind == Factory.CellKind.MACHINE and cell.machine_origin != coordinate:
			continue  # store each machine once, at its origin
		data["cells"].append(capture_cell(coordinate, cell))
	return data

static func capture_cell(coordinate: Vector2i, cell: Cell) -> Dictionary:
	var entry := { "x": coordinate.x, "y": coordinate.y }
	match cell.kind:
		Factory.CellKind.BELT:
			entry["kind"] = "belt"
			entry["in"] = cell.input_direction
			entry["out"] = cell.output_direction
			entry["item"] = capture_item(cell.item)
		Factory.CellKind.ROUTER:
			entry["kind"] = "router"
			entry["router"] = cell.router_kind
			entry["in"] = cell.input_direction
			entry["out"] = cell.output_direction
			entry["rr"] = cell.round_robin_index
			entry["item"] = capture_item(cell.item)
		Factory.CellKind.MACHINE:
			var machine := cell.machine
			entry["kind"] = "machine"
			entry["id"] = String(machine.definition.id)
			entry["orient"] = machine.orientation
			entry["recipe"] = String(machine.recipe.output_id) if machine.recipe != null else ""
			entry["stored"] = machine.stored
			entry["progress"] = machine.progress
			entry["output_count"] = machine.output_count
			entry["output_item"] = String(machine.output_item.id) if machine.output_item != null else ""
			entry["output_loadout"] = capture_loadout(machine.output_loadout)
			entry["inputs"] = capture_inputs(machine)
	return entry

static func capture_item(item) -> Dictionary:
	if item == null:
		return {}
	return { "id": String(item.definition.id), "offset": item.offset, "loadout": capture_loadout(item.loadout) }

static func capture_loadout(loadout) -> Array:
	if loadout == null:
		return []
	return [String(loadout.legs.id), String(loadout.torso.id), String(loadout.head.id), String(loadout.arms.id)]

static func capture_inputs(machine) -> Dictionary:
	var result := {}
	if machine.definition.kind == MachineDef.Kind.ASSEMBLER:
		for slot in machine.inputs:
			result[str(slot)] = String(machine.inputs[slot].id)
	else:
		for input_id in machine.inputs:
			result[String(input_id)] = machine.inputs[input_id]
	return result

static func restore_state(factory: Factory, data: Dictionary) -> void:
	GameManager.current_save_name = data.get("name", "")
	factory.current_wave = int(data.get("wave", 1))
	factory.played_seconds = float(data.get("played_seconds", 0.0))
	Unlocks.from_list(data.get("unlocks", []))
	factory.build_ingots = int(data.get("build_ingots", Factory.STARTING_BUILD_INGOTS))
	factory.build_time_left = float(data.get("build_time_left", Factory.WAVE_BUILD_TIME))
	Sim.speed = float(data.get("speed", 1.0))
	Run.shuttle_robots.clear()
	for arr in data.get("shuttle_robots", []):
		var loadout = loadout_from_array(arr)
		if loadout != null:
			Run.shuttle_robots.append(loadout)
	restore_cells(factory, data)

# rebuild only the placed cells -- used by the menu preview, which must not touch run/global state
static func restore_cells(factory: Factory, data: Dictionary) -> void:
	factory.cells.clear()
	for entry in data.get("cells", []):
		if entry.get("kind", "") == "machine":
			restore_machine(factory, entry)          # machines first so their cells exist
	for entry in data.get("cells", []):
		var kind: String = entry.get("kind", "")
		if kind == "belt" or kind == "router":
			restore_track(factory, entry, kind)

static func restore_machine(factory: Factory, entry: Dictionary) -> void:
	var origin := Vector2i(int(entry["x"]), int(entry["y"]))
	var machine_id := StringName(entry["id"])
	var recipe_override := recipe_for(machine_id, StringName(entry.get("recipe", "")))
	if not factory._create_machine(origin, machine_id, int(entry.get("orient", 0)), recipe_override):
		return
	var machine: Machine = factory.cells[origin].machine
	machine.stored = int(entry.get("stored", 0))
	machine.progress = float(entry.get("progress", 0.0))
	machine.output_count = int(entry.get("output_count", 0))
	var output_id := StringName(entry.get("output_item", ""))
	machine.output_item = Database.item(output_id) if output_id != &"" else null
	machine.output_loadout = loadout_from_array(entry.get("output_loadout", []))
	restore_inputs(machine, entry.get("inputs", {}))

static func recipe_for(machine_id: StringName, output_id: StringName) -> Recipe:
	if output_id == &"":
		return null
	var def: MachineDef = Database.machine(machine_id)
	if def == null:
		return null
	for recipe in def.recipes:
		if recipe.output_id == output_id:
			return recipe
	if def.recipe != null and def.recipe.output_id == output_id:
		return def.recipe
	return null

static func restore_inputs(machine, inputs: Dictionary) -> void:
	if machine.definition.kind == MachineDef.Kind.ASSEMBLER:
		for slot_key in inputs:
			machine.inputs[int(slot_key)] = Database.item(StringName(inputs[slot_key]))
	else:
		for id_key in inputs:
			machine.inputs[StringName(id_key)] = int(inputs[id_key])

static func restore_track(factory: Factory, entry: Dictionary, kind: String) -> void:
	var coordinate := Vector2i(int(entry["x"]), int(entry["y"]))
	var cell := Cell.new()
	cell.input_direction = int(entry.get("in", 0))
	cell.output_direction = int(entry.get("out", 0))
	cell.item = item_from_dict(entry.get("item", {}))
	if kind == "router":
		cell.kind = Factory.CellKind.ROUTER
		cell.router_kind = int(entry.get("router", Factory.RouterKind.SPLITTER))
		cell.round_robin_index = int(entry.get("rr", 0))
	else:
		cell.kind = Factory.CellKind.BELT
	factory.cells[coordinate] = cell

static func item_from_dict(d: Dictionary):
	if d.is_empty():
		return null
	var definition: ItemDef = Database.item(StringName(d.get("id", "")))
	if definition == null:
		return null
	var item := Item.new(definition)
	item.offset = float(d.get("offset", 0.0))
	item.loadout = loadout_from_array(d.get("loadout", []))
	return item

static func loadout_from_array(arr):
	if arr == null or arr.size() < 4:
		return null
	var loadout := RobotLoadout.new()
	loadout.legs = Database.item(StringName(arr[0]))
	loadout.torso = Database.item(StringName(arr[1]))
	loadout.head = Database.item(StringName(arr[2]))
	loadout.arms = Database.item(StringName(arr[3]))
	return loadout
