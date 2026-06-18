extends Node2D
## The factory floor: place belts and machines and route scrap through them.
## Belts and machines have an input side and an output side, so items only flow the way they face.

const CELL_SIZE := 32
const ITEM_SIZE := 14.0
const BELT_SPEED := 1.0  # cells per second (60 a minute at tier 1). Sim.speed scales it.
# where a stopped item sits: right at the edge, still on the belt
const EDGE_REST_OFFSET := 1.0 - (ITEM_SIZE * 0.5) / CELL_SIZE
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const GRID_COLUMNS := 40
const GRID_ROWS := 22
const DEPO_START_SCRAP := 1000
const BELT_FRAMES_PER_SECOND := 8.0
const STARTING_BUILD_INGOTS := 120
const BUILD_INGOT_CAP := 999
const BELT_COST := 5
const SPLITTER_COST := 15
const MERGER_COST := 15
const ZOOM_MIN := 0.75
const ZOOM_MAX := 2.0
const ZOOM_STEP := 0.15
const PAN_MARGIN_CELLS := 5  # how far past the floor the view may scroll
const WAVE_BUILD_TIME := 240.0

enum CellKind { BELT, MACHINE, ROUTER }
enum RouterKind { SPLITTER, MERGER }
enum Tool { BELT, FORGE, BANK, CRAFTER, ASSEMBLER, SPLITTER, MERGER }

const TOOL_NAMES := ["Belt", "Forge", "Bank", "Crafter", "Assembler", "Splitter", "Merger"]
const TOOL_MACHINE := { Tool.FORGE: &"forge", Tool.BANK: &"bank", Tool.CRAFTER: &"crafter", Tool.ASSEMBLER: &"assembler" }

class Item:
	var definition: ItemDef
	var offset: float = 0.0  # 0 at the input edge, 1 at the output edge
	var loadout: RobotLoadout = null   # set on assembled-robot items
	var route_entry: int = 0           # router transit: side it came in
	var route_exit: int = -1           # router transit: side it's leaving (-1 = not chosen yet)
	func _init(item_definition: ItemDef) -> void:
		definition = item_definition

class Machine:
	var definition: MachineDef
	var origin: Vector2i           # top-left cell of the footprint
	var orientation: int = 0       # 0-3 quarter turns
	var footprint := Vector2i.ONE  # rotated size in cells
	var world_ports: Array = []    # { coord, side, role } in world space
	var recipe: Recipe = null      # what this crafter is set to make
	var progress: float = 0.0
	var inputs: Dictionary = {}    # crafter: item id -> count; assembler: slot -> ItemDef
	var output_item: ItemDef = null
	var output_count: int = 0      # finished items waiting to leave
	var output_loadout: RobotLoadout = null  # assembler: the robot waiting to leave
	var stored: int = 0            # source reservoir (the depo)

class Cell:
	var kind: int
	var input_direction: int = 2   # belt/router: side items come in from
	var output_direction: int = 0  # belt/router: side items go out
	var item: Item = null          # belt or router: one item at a time
	var machine: Machine = null    # set on every cell a machine covers
	var machine_origin := Vector2i.ZERO  # which machine cell is the origin
	var router_kind: int = 0       # splitter or merger, on router cells
	var round_robin_index: int = 0 # splitter: next output side to try

var cells: Dictionary = {}  # Vector2i grid coordinate -> Cell
var depo_coordinate := Vector2i(1, 6)
var shuttle_coordinate := Vector2i(GRID_COLUMNS - 2, 6)
var build_ingots := STARTING_BUILD_INGOTS
var selected_tool := Tool.BELT
var crafter_recipe_index := 0  # which part a new crafter will make
var placement_direction := 0   # facing used when you place something
var hovered_coordinate := Vector2i.ZERO

var belt_frames: Array[Texture2D] = []
var belt_animation_time := 0.0
@export var show_animations := true   # turn off to see plain placeholders for debugging

@onready var camera: Camera2D = $Camera2D

# while dragging belts, each one links to the last so corners form on their own
var has_chain_anchor := false
var chain_anchor := Vector2i.ZERO

# middle mouse: drag to pan, or click (no drag) to pick the part under the cursor
var panning := false
var pan_drag_distance := 0.0

var build_time_left := WAVE_BUILD_TIME
var launch_armed := false

func _ready() -> void:
	_load_belt_frames()
	_create_machine(depo_coordinate, &"depo", 0)
	_create_machine(shuttle_coordinate, &"shuttle", 0)
	_clamp_camera()

func _load_belt_frames() -> void:
	var index := 1
	while true:
		var path := "res://sprites/belts/scrap_belt_straight/Straight Belt %d.png" % index
		if not ResourceLoader.exists(path):
			break
		belt_frames.append(load(path))
		index += 1

func _process(delta: float) -> void:
	var scaled_delta := delta * Sim.speed
	belt_animation_time += scaled_delta
	build_time_left = maxf(0.0, build_time_left - scaled_delta)
	_advance_items(scaled_delta)
	_tick_machines(scaled_delta)
	_advance_routers(scaled_delta)
	hovered_coordinate = _world_to_cell(get_global_mouse_position())
	queue_redraw()

# --- belt simulation ---

func _advance_items(scaled_delta: float) -> void:
	# grab the filled cells first so an item moves at most one cell per frame
	var occupied_coordinates := []
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.BELT and cell.item != null:
			occupied_coordinates.append(coordinate)
	for coordinate in occupied_coordinates:
		var cell: Cell = cells.get(coordinate)
		if cell == null or cell.item == null:
			continue
		var item: Item = cell.item
		var next_coordinate: Vector2i = coordinate + DIRECTIONS[cell.output_direction]
		var next_cell: Cell = cells.get(next_coordinate)
		var can_hand_off := next_cell != null \
			and _accepts_from(next_cell, next_coordinate, coordinate) \
			and _has_room_for(next_cell, item.definition)
		item.offset += BELT_SPEED * scaled_delta
		if can_hand_off:
			if item.offset >= 1.0:
				_hand_off(item, coordinate, next_coordinate)
		else:
			item.offset = min(item.offset, EDGE_REST_OFFSET)  # nowhere to go, sit at the edge

func _hand_off(item: Item, from_coordinate: Vector2i, into_coordinate: Vector2i) -> void:
	var into_cell: Cell = cells[into_coordinate]
	if into_cell.kind == CellKind.MACHINE:
		_deposit_into_machine(into_cell.machine, item)
	elif into_cell.kind == CellKind.ROUTER:
		_enter_router(item, from_coordinate, into_coordinate)
		into_cell.item = item
	else:
		item.offset = clamp(item.offset - 1.0, 0.0, 0.99)
		into_cell.item = item
	cells[from_coordinate].item = null

func _enter_router(item: Item, from_coordinate: Vector2i, router_coordinate: Vector2i) -> void:
	item.offset = 0.0
	item.route_entry = _direction_index(from_coordinate - router_coordinate)
	item.route_exit = -1

# --- machine simulation ---

func _tick_machines(scaled_delta: float) -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind != CellKind.MACHINE or cell.machine_origin != coordinate:
			continue  # tick each machine once, at its origin cell
		match cell.machine.definition.kind:
			MachineDef.Kind.SOURCE: _tick_source(cell)
			MachineDef.Kind.CRAFTER: _tick_crafter(cell, scaled_delta)
			MachineDef.Kind.ASSEMBLER: _tick_assembler(cell, scaled_delta)
			MachineDef.Kind.STORAGE: _tick_storage(cell)

func _tick_source(cell: Cell) -> void:
	var machine := cell.machine
	if machine.stored <= 0:
		return
	if _push_machine_output(machine, Database.item(machine.definition.source_item)):
		machine.stored -= 1

func _tick_crafter(cell: Cell, scaled_delta: float) -> void:
	var machine := cell.machine
	var recipe := machine.recipe
	var output_definition := Database.item(recipe.output_id)
	if machine.output_count < output_definition.stack_size and _has_recipe_inputs(machine, recipe):
		machine.progress += scaled_delta
		if machine.progress >= recipe.craft_time:
			machine.progress = 0.0
			_consume_recipe_inputs(machine, recipe)
			machine.output_item = output_definition
			machine.output_count += recipe.output_count
	if machine.output_count > 0 and _push_machine_output(machine, machine.output_item):
		machine.output_count -= 1

func _tick_storage(cell: Cell) -> void:
	# the bank dispenses from the shared build reserve
	if build_ingots <= 0:
		return
	if _push_machine_output(cell.machine, Database.item(cell.machine.definition.storage_item)):
		build_ingots -= 1

func _tick_assembler(cell: Cell, scaled_delta: float) -> void:
	var machine := cell.machine
	if machine.output_count == 0 and _assembler_ready(machine):
		machine.progress += scaled_delta
		if machine.progress >= machine.recipe.craft_time:
			machine.progress = 0.0
			machine.output_loadout = _build_loadout(machine)
			machine.output_count = 1
			machine.inputs.clear()
	if machine.output_count > 0 and _push_machine_output(machine, Database.item(&"robot"), machine.output_loadout):
		machine.output_count -= 1
		machine.output_loadout = null

func _assembler_ready(machine: Machine) -> bool:
	return machine.inputs.has(ItemDef.Slot.LEGS) and machine.inputs.has(ItemDef.Slot.TORSO) \
		and machine.inputs.has(ItemDef.Slot.HEAD) and machine.inputs.has(ItemDef.Slot.ARMS)

func _build_loadout(machine: Machine) -> RobotLoadout:
	var loadout := RobotLoadout.new()
	loadout.legs = machine.inputs[ItemDef.Slot.LEGS]
	loadout.torso = machine.inputs[ItemDef.Slot.TORSO]
	loadout.head = machine.inputs[ItemDef.Slot.HEAD]
	loadout.arms = machine.inputs[ItemDef.Slot.ARMS]
	return loadout

# push a freshly made item out the output side, into a belt, router, or machine
func _push_item(coordinate: Vector2i, item_definition: ItemDef, loadout: RobotLoadout = null) -> bool:
	var cell: Cell = cells[coordinate]
	var new_item := Item.new(item_definition)
	new_item.loadout = loadout
	return _deliver_to(coordinate, coordinate + DIRECTIONS[cell.output_direction], new_item)

# move an item into a neighbor (belt, router, or machine) if it'll take it
func _deliver_to(from_coordinate: Vector2i, target_coordinate: Vector2i, item: Item) -> bool:
	if not _can_deliver(from_coordinate, target_coordinate, item.definition):
		return false
	var target: Cell = cells[target_coordinate]
	if target.kind == CellKind.MACHINE:
		_deposit_into_machine(target.machine, item)
	elif target.kind == CellKind.ROUTER:
		_enter_router(item, from_coordinate, target_coordinate)
		target.item = item
	else:
		item.offset = 0.0
		target.item = item
	return true

func _can_deliver(from_coordinate: Vector2i, target_coordinate: Vector2i, item_definition: ItemDef) -> bool:
	var target: Cell = cells.get(target_coordinate)
	return target != null and _accepts_from(target, target_coordinate, from_coordinate) and _has_room_for(target, item_definition)

func _deposit_into_machine(machine: Machine, item: Item) -> void:
	match machine.definition.kind:
		MachineDef.Kind.CRAFTER:
			machine.inputs[item.definition.id] = machine.inputs.get(item.definition.id, 0) + 1
		MachineDef.Kind.STORAGE:
			build_ingots = min(build_ingots + 1, BUILD_INGOT_CAP)
		MachineDef.Kind.ASSEMBLER:
			machine.inputs[item.definition.slot] = item.definition
		MachineDef.Kind.SHUTTLE:
			if item.loadout != null:
				Run.pending_robots.append(item.loadout)

func _has_recipe_inputs(machine: Machine, recipe: Recipe) -> bool:
	for input_id in recipe.inputs:
		if machine.inputs.get(input_id, 0) < recipe.inputs[input_id]:
			return false
	return true

func _consume_recipe_inputs(machine: Machine, recipe: Recipe) -> void:
	for input_id in recipe.inputs:
		machine.inputs[input_id] -= recipe.inputs[input_id]

# --- splitters & mergers ---

# items travel through a router: in edge -> center -> out edge, waiting at center if the exit is blocked
func _advance_routers(scaled_delta: float) -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind != CellKind.ROUTER:
			continue
		if cell.item == null:
			if cell.router_kind == RouterKind.MERGER:
				_advance_merger_intake(coordinate, cell)
			continue
		var item: Item = cell.item
		if item.offset < 0.5:
			item.offset = min(item.offset + BELT_SPEED * scaled_delta, 0.5)
			continue
		if item.route_exit == -1:
			item.route_exit = _choose_router_exit(coordinate, cell, item)
			if item.route_exit == -1:
				continue  # nowhere to go yet, sit at the center
		item.offset += BELT_SPEED * scaled_delta
		if item.offset >= 1.0:
			if _deliver_to(coordinate, coordinate + DIRECTIONS[item.route_exit], item):
				if cell.router_kind == RouterKind.SPLITTER:
					cell.round_robin_index = (item.route_exit + 1) % DIRECTIONS.size()
				cell.item = null
			else:
				item.offset = 1.0  # exit blocked, wait at the edge

func _choose_router_exit(coordinate: Vector2i, cell: Cell, item: Item) -> int:
	if cell.router_kind == RouterKind.MERGER:
		var exit_direction := cell.output_direction
		return exit_direction if _can_deliver(coordinate, coordinate + DIRECTIONS[exit_direction], item.definition) else -1
	return _next_splitter_exit(coordinate, cell)

# splitter commits to the next connected output in order, skipping only sides with no connection
func _next_splitter_exit(coordinate: Vector2i, cell: Cell) -> int:
	for step in range(DIRECTIONS.size()):
		var direction := (cell.round_robin_index + step) % DIRECTIONS.size()
		if direction == cell.input_direction:
			continue
		if _has_connection(coordinate, direction):
			return direction
	return -1

func _has_connection(coordinate: Vector2i, side: int) -> bool:
	var neighbor_coordinate: Vector2i = coordinate + DIRECTIONS[side]
	var neighbor: Cell = cells.get(neighbor_coordinate)
	return neighbor != null and _connects_from(neighbor, neighbor_coordinate, coordinate)

# a merger steps to the next connected input that has something ready, in order, for an even merge
func _advance_merger_intake(coordinate: Vector2i, cell: Cell) -> void:
	for step in range(1, DIRECTIONS.size() + 1):
		var side := (cell.round_robin_index + step) % DIRECTIONS.size()
		if side != cell.output_direction and _input_ready(coordinate, side):
			cell.round_robin_index = side
			return

func _input_ready(coordinate: Vector2i, side: int) -> bool:
	var source_coordinate: Vector2i = coordinate + DIRECTIONS[side]
	var source: Cell = cells.get(source_coordinate)
	if source == null or not _outputs_into(source_coordinate, coordinate):
		return false
	match source.kind:
		CellKind.BELT:
			return source.item != null
		CellKind.ROUTER:
			return source.item != null and source.route_exit == _direction_index(coordinate - source_coordinate)
		CellKind.MACHINE:
			return _machine_can_output(source.machine)
	return false

func _machine_can_output(machine: Machine) -> bool:
	match machine.definition.kind:
		MachineDef.Kind.SOURCE:
			return machine.stored > 0
		MachineDef.Kind.STORAGE:
			return build_ingots > 0
	return machine.output_count > 0

# --- connection rules (shared by belts and machines) ---

# is there an input here facing that spot (topology only; ignores whose turn it is)
func _connects_from(cell: Cell, cell_coordinate: Vector2i, from_coordinate: Vector2i) -> bool:
	match cell.kind:
		CellKind.BELT:
			return cell_coordinate + DIRECTIONS[cell.input_direction] == from_coordinate
		CellKind.MACHINE:
			var side := _direction_index(from_coordinate - cell_coordinate)
			return side != -1 and _machine_has_port(cell.machine, cell_coordinate, side, MachinePort.Role.INPUT)
		CellKind.ROUTER:
			if cell.router_kind == RouterKind.SPLITTER:
				return cell_coordinate + DIRECTIONS[cell.input_direction] == from_coordinate
			# a merger's inputs are every side except its output
			var from_direction := _direction_index(from_coordinate - cell_coordinate)
			return from_direction != -1 and from_direction != cell.output_direction
	return false

# will this cell actually take a pushed item right now (a merger only opens its current input side)
func _accepts_from(cell: Cell, cell_coordinate: Vector2i, from_coordinate: Vector2i) -> bool:
	if cell.kind == CellKind.ROUTER and cell.router_kind == RouterKind.MERGER:
		var side := _direction_index(from_coordinate - cell_coordinate)
		return side != -1 and side != cell.output_direction and side == cell.round_robin_index
	return _connects_from(cell, cell_coordinate, from_coordinate)

# does the cell over there feed into this one
func _outputs_into(source_coordinate: Vector2i, target_coordinate: Vector2i) -> bool:
	var source: Cell = cells.get(source_coordinate)
	if source == null:
		return false
	if source.kind == CellKind.MACHINE:
		var side := _direction_index(target_coordinate - source_coordinate)
		return side != -1 and _machine_has_port(source.machine, source_coordinate, side, MachinePort.Role.OUTPUT)
	if source.kind == CellKind.ROUTER and source.router_kind == RouterKind.SPLITTER:
		# a splitter sends out every side except its input
		var direction := _direction_index(target_coordinate - source_coordinate)
		return direction != -1 and direction != source.input_direction
	return source_coordinate + DIRECTIONS[source.output_direction] == target_coordinate

func _has_room_for(cell: Cell, item_definition: ItemDef) -> bool:
	if cell.kind == CellKind.BELT or cell.kind == CellKind.ROUTER:
		return cell.item == null
	return _machine_accepts(cell.machine, item_definition)

func _machine_accepts(machine: Machine, item_definition: ItemDef) -> bool:
	match machine.definition.kind:
		MachineDef.Kind.CRAFTER:
			var recipe := machine.recipe
			if not recipe.inputs.has(item_definition.id):
				return false
			return machine.inputs.get(item_definition.id, 0) < item_definition.stack_size
		MachineDef.Kind.STORAGE:
			return item_definition.id == machine.definition.storage_item and build_ingots < BUILD_INGOT_CAP
		MachineDef.Kind.ASSEMBLER:
			return item_definition.slot != ItemDef.Slot.NONE and not machine.inputs.has(item_definition.slot)
		MachineDef.Kind.SHUTTLE:
			return item_definition.id == &"robot"
	return false

# --- placement ---

func _unhandled_input(event: InputEvent) -> void:
	# clicking or typing anything in the world cancels an armed launch
	if launch_armed and ((event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed)):
		disarm_launch()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_place_at(_world_to_cell(get_global_mouse_position()))
			else:
				has_chain_anchor = false               # done dragging
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_remove_cell(_world_to_cell(get_global_mouse_position()))
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_adjust_zoom(ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_adjust_zoom(-ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				panning = true
				pan_drag_distance = 0.0
			else:
				panning = false
				if pan_drag_distance < 6.0:   # a click, not a drag: pick the part to build
					_pick_tool_at(_world_to_cell(get_global_mouse_position()))
	elif event is InputEventMouseMotion:
		if panning:
			camera.position -= event.relative / camera.zoom.x
			pan_drag_distance += event.relative.length()
			_clamp_camera()
		elif event.button_mask & MOUSE_BUTTON_MASK_LEFT and selected_tool == Tool.BELT:
			_try_place_belt(_world_to_cell(get_global_mouse_position()))
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_B: selected_tool = Tool.BELT
			KEY_F: selected_tool = Tool.FORGE
			KEY_K: selected_tool = Tool.BANK
			KEY_C: _select_crafter_tool()
			KEY_A: selected_tool = Tool.ASSEMBLER
			KEY_S: selected_tool = Tool.SPLITTER
			KEY_M: selected_tool = Tool.MERGER
			KEY_R: placement_direction = (placement_direction + 1) % DIRECTIONS.size()
			KEY_1: Sim.speed = 0.5
			KEY_2: Sim.speed = 1.0
			KEY_3: Sim.speed = 2.0

func _place_at(coordinate: Vector2i) -> void:
	if selected_tool == Tool.BELT:
		has_chain_anchor = false                       # start a new run of belts
		_try_place_belt(coordinate)
		return
	if selected_tool == Tool.SPLITTER:
		_place_router(coordinate, RouterKind.SPLITTER)
		return
	if selected_tool == Tool.MERGER:
		_place_router(coordinate, RouterKind.MERGER)
		return
	var recipe_override: Recipe = null
	if selected_tool == Tool.CRAFTER:
		recipe_override = _selected_crafter_recipe()
	_place_machine(coordinate, TOOL_MACHINE[selected_tool], recipe_override)

func _place_router(coordinate: Vector2i, router_kind: int) -> void:
	var cost := SPLITTER_COST if router_kind == RouterKind.SPLITTER else MERGER_COST
	if cells.has(coordinate) or not _afford(cost):
		return
	var cell := Cell.new()
	cell.kind = CellKind.ROUTER
	cell.router_kind = router_kind
	cell.input_direction = _opposite_direction(placement_direction)
	cell.output_direction = placement_direction
	cells[coordinate] = cell
	build_ingots -= cost
	for direction in range(DIRECTIONS.size()):
		_snap_belt(coordinate + DIRECTIONS[direction])

func _afford(cost: int) -> bool:
	return build_ingots >= cost

func _select_crafter_tool() -> void:
	if selected_tool == Tool.CRAFTER:
		var count := Database.machine(&"crafter").recipes.size()
		crafter_recipe_index = (crafter_recipe_index + 1) % count
	else:
		selected_tool = Tool.CRAFTER

func _selected_crafter_recipe() -> Recipe:
	return Database.machine(&"crafter").recipes[crafter_recipe_index]

func _try_place_belt(coordinate: Vector2i) -> void:
	if cells.has(coordinate) or not _afford(BELT_COST):
		return
	var input_direction: int
	var output_direction: int
	if has_chain_anchor and _are_adjacent(chain_anchor, coordinate):
		var step := _direction_index(coordinate - chain_anchor)
		var anchor_cell: Cell = cells.get(chain_anchor)
		if anchor_cell != null and anchor_cell.kind == CellKind.BELT:
			anchor_cell.output_direction = step        # point the last belt at this one so it bends
		input_direction = _opposite_direction(step)
		output_direction = step
	else:
		output_direction = placement_direction
		input_direction = _opposite_direction(placement_direction)
	var belt_cell := Cell.new()
	belt_cell.kind = CellKind.BELT
	belt_cell.input_direction = input_direction
	belt_cell.output_direction = output_direction
	cells[coordinate] = belt_cell
	build_ingots -= BELT_COST
	_snap_belt(coordinate)
	chain_anchor = coordinate
	has_chain_anchor = true

func _place_machine(coordinate: Vector2i, machine_id: StringName, recipe_override: Recipe = null) -> void:
	var cost: int = Database.machine(machine_id).build_cost
	if not _afford(cost):
		return
	if _create_machine(coordinate, machine_id, placement_direction, recipe_override):
		build_ingots -= cost

func _remove_cell(coordinate: Vector2i) -> void:
	var cell: Cell = cells.get(coordinate)
	if cell == null:
		return
	if cell.kind == CellKind.MACHINE:
		var machine := cell.machine
		if _is_prefab(machine.definition.kind):
			return  # the depo and shuttle stay put
		build_ingots = min(build_ingots + machine.definition.build_cost, BUILD_INGOT_CAP)
		for machine_cell in _machine_world_cells(machine):
			cells.erase(machine_cell)
		return
	build_ingots = min(build_ingots + _cost_of_cell(cell), BUILD_INGOT_CAP)
	cells.erase(coordinate)

func _is_prefab(machine_kind: int) -> bool:
	return machine_kind == MachineDef.Kind.SOURCE or machine_kind == MachineDef.Kind.SHUTTLE

func _cost_of_cell(cell: Cell) -> int:
	match cell.kind:
		CellKind.BELT:
			return BELT_COST
		CellKind.ROUTER:
			return SPLITTER_COST if cell.router_kind == RouterKind.SPLITTER else MERGER_COST
		CellKind.MACHINE:
			return cell.machine.definition.build_cost
	return 0

func _are_adjacent(first: Vector2i, second: Vector2i) -> bool:
	return DIRECTIONS.has(second - first)

func _direction_index(step: Vector2i) -> int:
	return DIRECTIONS.find(step)

func _opposite_direction(direction: int) -> int:
	return (direction + 2) % DIRECTIONS.size()

# --- machine footprints & ports ---

func _create_machine(origin: Vector2i, machine_id: StringName, orientation: int, recipe_override: Recipe = null) -> bool:
	var def: MachineDef = Database.machine(machine_id)
	if not _machine_fits(origin, def, orientation):
		return false
	var machine := Machine.new()
	machine.definition = def
	machine.recipe = recipe_override if recipe_override != null else def.recipe
	machine.origin = origin
	machine.orientation = orientation
	machine.footprint = _rotated_footprint(def.footprint, orientation)
	machine.world_ports = _world_ports(def, origin, orientation)
	if def.kind == MachineDef.Kind.SOURCE:
		machine.stored = DEPO_START_SCRAP
	for offset in _footprint_offsets(def, orientation):
		var cell := Cell.new()
		cell.kind = CellKind.MACHINE
		cell.machine = machine
		cell.machine_origin = origin
		cells[origin + offset] = cell
	for machine_cell in _machine_world_cells(machine):
		for direction in range(DIRECTIONS.size()):
			_snap_belt(machine_cell + DIRECTIONS[direction])
	return true

func _machine_fits(origin: Vector2i, def: MachineDef, orientation: int) -> bool:
	for offset in _footprint_offsets(def, orientation):
		var coordinate: Vector2i = origin + offset
		if cells.has(coordinate):
			return false
		if coordinate.x < 0 or coordinate.y < 0 or coordinate.x >= GRID_COLUMNS or coordinate.y >= GRID_ROWS:
			return false
	return true

func _footprint_offsets(def: MachineDef, orientation: int) -> Array:
	var offsets := []
	for x in range(def.footprint.x):
		for y in range(def.footprint.y):
			offsets.append(_rotate_cell(Vector2i(x, y), orientation, def.footprint))
	return offsets

func _machine_world_cells(machine: Machine) -> Array:
	var result := []
	for x in range(machine.footprint.x):
		for y in range(machine.footprint.y):
			result.append(machine.origin + Vector2i(x, y))
	return result

func _world_ports(def: MachineDef, origin: Vector2i, orientation: int) -> Array:
	var result := []
	for port in def.ports:
		result.append({
			"coord": origin + _rotate_cell(port.cell, orientation, def.footprint),
			"side": _rotate_side(port.side, orientation),
			"role": port.role,
		})
	return result

func _rotate_cell(local: Vector2i, orientation: int, footprint: Vector2i) -> Vector2i:
	match orientation:
		1: return Vector2i(footprint.y - 1 - local.y, local.x)
		2: return Vector2i(footprint.x - 1 - local.x, footprint.y - 1 - local.y)
		3: return Vector2i(local.y, footprint.x - 1 - local.x)
	return local

func _rotated_footprint(footprint: Vector2i, orientation: int) -> Vector2i:
	return Vector2i(footprint.y, footprint.x) if orientation % 2 == 1 else footprint

func _rotate_side(side: int, orientation: int) -> int:
	return (side + orientation) % DIRECTIONS.size()

func _machine_has_port(machine: Machine, coordinate: Vector2i, side: int, role: int) -> bool:
	for port in machine.world_ports:
		if port.role == role and port.coord == coordinate and port.side == side:
			return true
	return false

func _machine_output_port(machine: Machine):
	for port in machine.world_ports:
		if port.role == MachinePort.Role.OUTPUT:
			return port
	return null

func _push_machine_output(machine: Machine, item_definition: ItemDef, loadout: RobotLoadout = null) -> bool:
	var port = _machine_output_port(machine)
	if port == null:
		return false
	var new_item := Item.new(item_definition)
	new_item.loadout = loadout
	return _deliver_to(port.coord, port.coord + DIRECTIONS[port.side], new_item)

# --- auto-connect ---
# when a belt goes down, hook a loose end up to a neighbor and bend the corner.
# leave sides that already connect alone.

func _snap_belt(coordinate: Vector2i) -> void:
	var cell: Cell = cells.get(coordinate)
	if cell == null or cell.kind != CellKind.BELT:
		return
	_snap_input_side(coordinate, cell)
	_snap_output_side(coordinate, cell)

func _snap_input_side(coordinate: Vector2i, cell: Cell) -> void:
	if _is_input_connected(coordinate, cell):
		return
	for direction in range(DIRECTIONS.size()):
		if direction == cell.output_direction:
			continue  # don't face input and output the same way
		var neighbor_coordinate: Vector2i = coordinate + DIRECTIONS[direction]
		var neighbor: Cell = cells.get(neighbor_coordinate)
		if neighbor == null:
			continue
		if _outputs_into(neighbor_coordinate, coordinate):
			cell.input_direction = direction          # neighbor already feeds us, point at it
			return
		if neighbor.kind == CellKind.BELT and not _is_output_connected(neighbor_coordinate, neighbor):
			var toward_us := _direction_index(coordinate - neighbor_coordinate)
			if neighbor.input_direction != toward_us:  # neighbor has a spare output, turn it our way
				neighbor.output_direction = toward_us
				cell.input_direction = direction
				return

func _snap_output_side(coordinate: Vector2i, cell: Cell) -> void:
	if _is_output_connected(coordinate, cell):
		return
	for direction in range(DIRECTIONS.size()):
		if direction == cell.input_direction:
			continue
		var neighbor_coordinate: Vector2i = coordinate + DIRECTIONS[direction]
		var neighbor: Cell = cells.get(neighbor_coordinate)
		if neighbor == null:
			continue
		if _connects_from(neighbor, neighbor_coordinate, coordinate):
			cell.output_direction = direction          # neighbor already takes from us
			return
		if neighbor.kind == CellKind.BELT and not _is_input_connected(neighbor_coordinate, neighbor):
			var from_us := _direction_index(coordinate - neighbor_coordinate)
			if neighbor.output_direction != from_us:   # neighbor has a spare input, turn it our way
				neighbor.input_direction = from_us
				cell.output_direction = direction
				return

func _is_input_connected(coordinate: Vector2i, cell: Cell) -> bool:
	return _outputs_into(coordinate + DIRECTIONS[cell.input_direction], coordinate)

func _is_output_connected(coordinate: Vector2i, cell: Cell) -> bool:
	var target_coordinate: Vector2i = coordinate + DIRECTIONS[cell.output_direction]
	var target: Cell = cells.get(target_coordinate)
	return target != null and _connects_from(target, target_coordinate, coordinate)

func _adjust_zoom(amount: float) -> void:
	var level := clampf(camera.zoom.x + amount, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(level, level)
	_clamp_camera()

# keep the view from scrolling more than PAN_MARGIN_CELLS past the floor on any side
func _clamp_camera() -> void:
	var view: Vector2 = get_viewport_rect().size / camera.zoom
	var margin := PAN_MARGIN_CELLS * CELL_SIZE
	var min_corner := Vector2(-margin, -margin)
	var max_corner := Vector2(GRID_COLUMNS * CELL_SIZE + margin, GRID_ROWS * CELL_SIZE + margin)
	var low := min_corner + view * 0.5
	var high := max_corner - view * 0.5
	var position := camera.position
	position.x = (min_corner.x + max_corner.x) * 0.5 if low.x > high.x else clampf(position.x, low.x, high.x)
	position.y = (min_corner.y + max_corner.y) * 0.5 if low.y > high.y else clampf(position.y, low.y, high.y)
	camera.position = position

# eyedropper: select the tool for whatever's under the cursor, matching its facing
func _pick_tool_at(coordinate: Vector2i) -> void:
	var cell: Cell = cells.get(coordinate)
	if cell == null:
		return
	match cell.kind:
		CellKind.BELT:
			selected_tool = Tool.BELT
			placement_direction = cell.output_direction
		CellKind.ROUTER:
			selected_tool = Tool.SPLITTER if cell.router_kind == RouterKind.SPLITTER else Tool.MERGER
			placement_direction = cell.output_direction
		CellKind.MACHINE:
			_pick_machine_tool(cell.machine)

func _pick_machine_tool(machine: Machine) -> void:
	placement_direction = machine.orientation
	match machine.definition.id:
		&"forge": selected_tool = Tool.FORGE
		&"bank": selected_tool = Tool.BANK
		&"assembler": selected_tool = Tool.ASSEMBLER
		&"crafter":
			selected_tool = Tool.CRAFTER
			var index := machine.definition.recipes.find(machine.recipe)
			if index != -1:
				crafter_recipe_index = index

func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / float(CELL_SIZE)), floori(world_position.y / float(CELL_SIZE)))

func _cell_center(coordinate: Vector2i) -> Vector2:
	return Vector2(coordinate) * CELL_SIZE + Vector2(CELL_SIZE, CELL_SIZE) * 0.5

func _quadratic_bezier(start: Vector2, control: Vector2, end: Vector2, t: float) -> Vector2:
	var inverse := 1.0 - t
	return inverse * inverse * start + 2.0 * inverse * t * control + t * t * end

# --- drawing ---

func _draw() -> void:
	# layers, bottom to top: placeholders, belt animation, items, machine UI
	_draw_grid()
	_draw_placeholders()
	if show_animations:
		_draw_belt_animations()
	_draw_items()
	_draw_machine_ui_layer()
	_draw_placement_preview()

func _draw_placeholders() -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		match cell.kind:
			CellKind.BELT:
				_draw_belt_placeholder(_cell_rect(coordinate), cell.input_direction, cell.output_direction, 1.0)
			CellKind.MACHINE:
				if cell.machine_origin == coordinate:
					_draw_machine_body(cell.machine, 1.0)
			CellKind.ROUTER:
				_draw_router_shape(_cell_rect(coordinate), cell.router_kind, cell.input_direction, cell.output_direction, 1.0)

func _draw_belt_animations() -> void:
	if belt_frames.is_empty():
		return
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.BELT and cell.input_direction == _opposite_direction(cell.output_direction):
			_draw_belt_frame(_cell_rect(coordinate), cell.output_direction, 1.0)

func _draw_items() -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.item == null:
			continue
		if cell.kind == CellKind.BELT:
			_draw_item(coordinate, cell)
		elif cell.kind == CellKind.ROUTER:
			_draw_router_item(coordinate, cell)

func _draw_machine_ui_layer() -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.MACHINE and cell.machine_origin == coordinate:
			_draw_machine_ui(cell)

func _cell_rect(coordinate: Vector2i) -> Rect2:
	return Rect2(Vector2(coordinate) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))

func _draw_grid() -> void:
	var grid_color := Color(1, 1, 1, 0.06)
	for column in range(GRID_COLUMNS + 1):
		draw_line(Vector2(column * CELL_SIZE, 0), Vector2(column * CELL_SIZE, GRID_ROWS * CELL_SIZE), grid_color)
	for row in range(GRID_ROWS + 1):
		draw_line(Vector2(0, row * CELL_SIZE), Vector2(GRID_COLUMNS * CELL_SIZE, row * CELL_SIZE), grid_color)

func _draw_belt_placeholder(rect: Rect2, input_direction: int, output_direction: int, alpha := 1.0) -> void:
	draw_rect(rect, Color(0.16, 0.16, 0.18, alpha))
	draw_rect(rect, Color(0, 0, 0, 0.4 * alpha), false, 1.0)
	var center := rect.position + rect.size * 0.5
	var input_vector := Vector2(DIRECTIONS[input_direction])
	var output_vector := Vector2(DIRECTIONS[output_direction])
	var arrow_color := Color(0.5, 0.9, 0.5, alpha)
	# arrow runs from the in side, through the center, to the out side
	var tail := center + input_vector * 8.0
	var head := center + output_vector * 8.0
	draw_line(tail, center, arrow_color, 2.0)
	draw_line(center, head, arrow_color, 2.0)
	var perpendicular := Vector2(-output_vector.y, output_vector.x)
	draw_line(head, head - output_vector * 5.0 + perpendicular * 4.0, arrow_color, 2.0)
	draw_line(head, head - output_vector * 5.0 - perpendicular * 4.0, arrow_color, 2.0)

func _draw_belt_frame(rect: Rect2, output_direction: int, alpha: float) -> void:
	var frame := int(belt_animation_time * BELT_FRAMES_PER_SECOND) % belt_frames.size()
	var center := rect.position + rect.size * 0.5
	# the art scrolls up by default, so add a quarter turn to line it up with the output direction
	draw_set_transform(center, (output_direction + 1) * PI * 0.5, Vector2.ONE)
	draw_texture_rect(belt_frames[frame], Rect2(-rect.size * 0.5, rect.size), false, Color(1, 1, 1, alpha))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _machine_rect(machine: Machine) -> Rect2:
	return Rect2(Vector2(machine.origin) * CELL_SIZE, Vector2(machine.footprint) * CELL_SIZE)

func _draw_machine_ui(cell: Cell) -> void:
	var machine := cell.machine
	var rect := _machine_rect(machine)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(3, 13), _machine_label(machine), 0, -1, 10, Color(1, 1, 1, 0.95))
	match machine.definition.kind:
		MachineDef.Kind.CRAFTER, MachineDef.Kind.ASSEMBLER:
			var fraction := clampf(machine.progress / machine.recipe.craft_time, 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 5), Vector2((rect.size.x - 4) * fraction, 3)), Color(0.5, 0.9, 0.5))
		MachineDef.Kind.STORAGE:
			draw_string(font, rect.position + Vector2(3, rect.size.y - 4), str(build_ingots), 0, -1, 10, Color(1, 1, 1, 0.9))
		MachineDef.Kind.SOURCE:
			draw_string(font, rect.position + Vector2(3, rect.size.y - 4), str(machine.stored), 0, -1, 10, Color(1, 1, 1, 0.9))
		MachineDef.Kind.SHUTTLE:
			draw_string(font, rect.position + Vector2(3, rect.size.y - 4), str(Run.pending_robots.size()), 0, -1, 10, Color(1, 1, 1, 0.9))

func _machine_label(machine: Machine) -> String:
	# a crafter shows what it's making; everything else shows its own name
	if machine.definition.kind == MachineDef.Kind.CRAFTER and not machine.definition.recipes.is_empty():
		return Database.item(machine.recipe.output_id).display_name
	return machine.definition.display_name

func _draw_machine_body(machine: Machine, alpha: float) -> void:
	var rect := _machine_rect(machine)
	var fill := machine.definition.color
	fill.a = alpha
	draw_rect(rect, fill)
	draw_rect(rect, Color(0, 0, 0, 0.5 * alpha), false, 1.0)
	for port in machine.world_ports:
		_draw_port(port.coord, port.side, port.role, alpha)

func _draw_port(coordinate: Vector2i, side: int, role: int, alpha: float) -> void:
	var center := _cell_center(coordinate)
	if role == MachinePort.Role.OUTPUT:
		_draw_side_arrow(center, side, Color(0.5, 0.9, 0.5, alpha))
	else:
		draw_line(center, center + Vector2(DIRECTIONS[side]) * (CELL_SIZE * 0.5 - 3.0), Color(0.7, 0.7, 0.7, alpha * 0.8), 1.5)

func _draw_router_shape(rect: Rect2, router_kind: int, input_direction: int, output_direction: int, alpha: float) -> void:
	var fill := _router_color(router_kind)
	fill.a = alpha
	draw_rect(rect, fill)
	draw_rect(rect, Color(0, 0, 0, 0.5 * alpha), false, 1.0)
	var label := "SPL" if router_kind == RouterKind.SPLITTER else "MRG"
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, 12), label, 0, -1, 8, Color(1, 1, 1, alpha))
	var center := rect.position + rect.size * 0.5
	for direction in range(DIRECTIONS.size()):
		var is_output := (router_kind == RouterKind.SPLITTER and direction != input_direction) \
			or (router_kind == RouterKind.MERGER and direction == output_direction)
		if is_output:
			_draw_side_arrow(center, direction, Color(0.5, 0.9, 0.5, alpha))
		else:
			draw_line(center, center + Vector2(DIRECTIONS[direction]) * (CELL_SIZE * 0.5 - 3.0), Color(0.7, 0.7, 0.7, alpha * 0.8), 1.5)

func _draw_side_arrow(center: Vector2, direction: int, color: Color) -> void:
	var vector := Vector2(DIRECTIONS[direction])
	var head := center + vector * (CELL_SIZE * 0.5 - 3.0)
	var perpendicular := Vector2(-vector.y, vector.x)
	draw_line(center, head, color, 2.0)
	draw_line(head, head - vector * 4.0 + perpendicular * 3.0, color, 2.0)
	draw_line(head, head - vector * 4.0 - perpendicular * 3.0, color, 2.0)

func _router_color(router_kind: int) -> Color:
	return Color(0.25, 0.45, 0.45) if router_kind == RouterKind.SPLITTER else Color(0.45, 0.30, 0.45)

func _draw_item(coordinate: Vector2i, cell: Cell) -> void:
	# item rides the path, curving through corners
	var center := _cell_center(coordinate)
	var entry := center + Vector2(DIRECTIONS[cell.input_direction]) * (CELL_SIZE * 0.5)
	var exit_point := center + Vector2(DIRECTIONS[cell.output_direction]) * (CELL_SIZE * 0.5)
	var item_position := _quadratic_bezier(entry, center, exit_point, cell.item.offset)
	_draw_item_shape(item_position, cell.item.definition.shape, cell.item.definition.color)

func _draw_router_item(coordinate: Vector2i, cell: Cell) -> void:
	# first half: in edge -> center; second half: center -> out edge
	var item := cell.item
	var center := _cell_center(coordinate)
	var position := center
	if item.offset < 0.5:
		var entry := center + Vector2(DIRECTIONS[item.route_entry]) * (CELL_SIZE * 0.5)
		position = entry.lerp(center, item.offset / 0.5)
	elif item.route_exit != -1:
		var exit_point := center + Vector2(DIRECTIONS[item.route_exit]) * (CELL_SIZE * 0.5)
		position = center.lerp(exit_point, (item.offset - 0.5) / 0.5)
	_draw_item_shape(position, item.definition.shape, item.definition.color)

func _draw_item_shape(center: Vector2, shape: ItemDef.Shape, color: Color) -> void:
	if shape == ItemDef.Shape.CIRCLE:
		draw_circle(center, ITEM_SIZE * 0.5, color)
	else:
		draw_colored_polygon(_item_polygon(shape, center), color)

func _item_polygon(shape: ItemDef.Shape, center: Vector2) -> PackedVector2Array:
	var half := ITEM_SIZE * 0.5
	var points := PackedVector2Array()
	match shape:
		ItemDef.Shape.TRAPEZOID:
			points = PackedVector2Array([Vector2(-half * 0.55, -half), Vector2(half * 0.55, -half), Vector2(half, half), Vector2(-half, half)])
		ItemDef.Shape.TRIANGLE:
			points = PackedVector2Array([Vector2(0, -half), Vector2(half, half), Vector2(-half, half)])
		ItemDef.Shape.DIAMOND:
			points = PackedVector2Array([Vector2(0, -half), Vector2(half, 0), Vector2(0, half), Vector2(-half, 0)])
		ItemDef.Shape.HEXAGON:
			for index in range(6):
				var angle := -PI * 0.5 + index * (PI / 3.0)
				points.append(Vector2(cos(angle), sin(angle)) * half)
		_:
			points = PackedVector2Array([Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)])
	var moved := PackedVector2Array()
	for point in points:
		moved.append(point + center)
	return moved

func _draw_placement_preview() -> void:
	var rect := _cell_rect(hovered_coordinate)
	var input_direction := _opposite_direction(placement_direction)
	match selected_tool:
		Tool.BELT:
			if cells.has(hovered_coordinate):
				draw_rect(rect, Color(1, 0.3, 0.3, 0.25))
			else:
				_draw_belt_placeholder(rect, input_direction, placement_direction, 0.5)
		Tool.SPLITTER:
			if cells.has(hovered_coordinate):
				draw_rect(rect, Color(1, 0.3, 0.3, 0.25))
			else:
				_draw_router_shape(rect, RouterKind.SPLITTER, input_direction, placement_direction, 0.5)
		Tool.MERGER:
			if cells.has(hovered_coordinate):
				draw_rect(rect, Color(1, 0.3, 0.3, 0.25))
			else:
				_draw_router_shape(rect, RouterKind.MERGER, input_direction, placement_direction, 0.5)
		_:
			_draw_machine_preview(TOOL_MACHINE[selected_tool])

func _draw_machine_preview(machine_id: StringName) -> void:
	var def: MachineDef = Database.machine(machine_id)
	var fits := _machine_fits(hovered_coordinate, def, placement_direction)
	var color := def.color if fits else Color(1.0, 0.3, 0.3)
	for offset in _footprint_offsets(def, placement_direction):
		var fill := color
		fill.a = 0.4
		draw_rect(_cell_rect(hovered_coordinate + offset), fill)
	for port in _world_ports(def, hovered_coordinate, placement_direction):
		_draw_port(port.coord, port.side, port.role, 0.7)
	var label := def.display_name
	if selected_tool == Tool.CRAFTER:
		label = Database.item(_selected_crafter_recipe().output_id).display_name
	draw_string(ThemeDB.fallback_font, _cell_rect(hovered_coordinate).position + Vector2(3, 13), label, 0, -1, 10, Color(1, 1, 1, 0.7))

# --- HUD data (read by the Hud layer) ---

func buildables() -> Array:
	return [
		{ "tool": Tool.BELT, "name": "Belt", "hotkey": "B", "cost": BELT_COST, "color": Color(0.16, 0.16, 0.18) },
		{ "tool": Tool.FORGE, "name": "Forge", "hotkey": "F", "cost": Database.machine(&"forge").build_cost, "color": Database.machine(&"forge").color },
		{ "tool": Tool.CRAFTER, "name": "Crafter", "hotkey": "C", "cost": Database.machine(&"crafter").build_cost, "color": Database.machine(&"crafter").color },
		{ "tool": Tool.ASSEMBLER, "name": "Assembler", "hotkey": "A", "cost": Database.machine(&"assembler").build_cost, "color": Database.machine(&"assembler").color },
		{ "tool": Tool.BANK, "name": "Bank", "hotkey": "K", "cost": Database.machine(&"bank").build_cost, "color": Database.machine(&"bank").color },
		{ "tool": Tool.SPLITTER, "name": "Splitter", "hotkey": "S", "cost": SPLITTER_COST, "color": _router_color(RouterKind.SPLITTER) },
		{ "tool": Tool.MERGER, "name": "Merger", "hotkey": "M", "cost": MERGER_COST, "color": _router_color(RouterKind.MERGER) },
	]

func select_build_tool(tool: int) -> void:
	if tool == Tool.CRAFTER:
		_select_crafter_tool()
	else:
		selected_tool = tool
	disarm_launch()

func scrap_total() -> int:
	var total := 0
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.MACHINE and cell.machine_origin == coordinate and cell.machine.definition.kind == MachineDef.Kind.SOURCE:
			total += cell.machine.stored
	return total

func robot_groups() -> Array:
	var counts := {}
	var order := []
	for loadout in Run.pending_robots:
		var signature: String = loadout.signature()
		if not counts.has(signature):
			counts[signature] = 0
			order.append(signature)
		counts[signature] += 1
	var result := []
	for signature in order:
		result.append({ "signature": signature, "count": counts[signature] })
	return result

func time_text() -> String:
	var seconds := int(ceil(build_time_left))
	return "%d:%02d" % [seconds / 60, seconds % 60]

func arm_launch() -> void:
	launch_armed = true

func confirm_launch() -> void:
	launch_armed = false
	# the army waits in Run.pending_robots, ready for the battle scene once it exists

func disarm_launch() -> void:
	launch_armed = false
