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

enum CellKind { BELT, MACHINE, ROUTER }
enum RouterKind { SPLITTER, MERGER }
enum Tool { BELT, FORGE, BANK, CRAFTER, ASSEMBLER, SPLITTER, MERGER }

const TOOL_NAMES := ["Belt", "Forge", "Bank", "Crafter", "Assembler", "Splitter", "Merger"]
const TOOL_MACHINE := { Tool.FORGE: &"forge", Tool.BANK: &"bank", Tool.CRAFTER: &"crafter", Tool.ASSEMBLER: &"assembler" }

class Item:
	var definition: ItemDef
	var offset: float = 0.0  # 0 at the input edge, 1 at the output edge
	var loadout: RobotLoadout = null   # set on assembled-robot items
	func _init(item_definition: ItemDef) -> void:
		definition = item_definition

class Machine:
	var definition: MachineDef
	var recipe: Recipe = null      # what this crafter is set to make
	var progress: float = 0.0
	var inputs: Dictionary = {}    # crafter: item id -> count; assembler: slot -> ItemDef
	var output_item: ItemDef = null
	var output_count: int = 0      # finished items waiting to leave
	var output_loadout: RobotLoadout = null  # assembler: the robot waiting to leave
	var stored: int = 0            # source reservoir (the depo)

class Cell:
	var kind: int
	var input_direction: int = 2   # side items come in from
	var output_direction: int = 0  # side items go out
	var item: Item = null          # belt or router: one item at a time
	var machine_id: StringName = &""
	var machine: Machine = null    # set on machine cells
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

# while dragging belts, each one links to the last so corners form on their own
var has_chain_anchor := false
var chain_anchor := Vector2i.ZERO

func _ready() -> void:
	_load_belt_frames()
	var depo := _new_machine_cell(&"depo")
	depo.machine.stored = DEPO_START_SCRAP
	cells[depo_coordinate] = depo
	cells[shuttle_coordinate] = _new_machine_cell(&"shuttle")

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
	_advance_items(scaled_delta)
	_tick_machines(scaled_delta)
	_tick_routers()
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
				_hand_off(item, cell, next_cell)
		else:
			item.offset = min(item.offset, EDGE_REST_OFFSET)  # nowhere to go, sit at the edge

func _hand_off(item: Item, from_cell: Cell, into_cell: Cell) -> void:
	if into_cell.kind == CellKind.MACHINE:
		_deposit_into_machine(into_cell.machine, item)
	else:
		into_cell.item = item
		if into_cell.kind == CellKind.BELT:
			item.offset = clamp(item.offset - 1.0, 0.0, 0.99)
		else:
			item.offset = 0.0   # a router just holds it until it pushes out
	from_cell.item = null

# --- machine simulation ---

func _tick_machines(scaled_delta: float) -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind != CellKind.MACHINE:
			continue
		match cell.machine.definition.kind:
			MachineDef.Kind.SOURCE: _tick_source(coordinate, cell)
			MachineDef.Kind.CRAFTER: _tick_crafter(coordinate, cell, scaled_delta)
			MachineDef.Kind.ASSEMBLER: _tick_assembler(coordinate, cell, scaled_delta)
			MachineDef.Kind.STORAGE: _tick_storage(coordinate, cell)

func _tick_source(coordinate: Vector2i, cell: Cell) -> void:
	var machine := cell.machine
	if machine.stored <= 0:
		return
	if _push_item(coordinate, Database.item(machine.definition.source_item)):
		machine.stored -= 1

func _tick_crafter(coordinate: Vector2i, cell: Cell, scaled_delta: float) -> void:
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
	if machine.output_count > 0 and _push_item(coordinate, machine.output_item):
		machine.output_count -= 1

func _tick_storage(coordinate: Vector2i, cell: Cell) -> void:
	# the bank dispenses from the shared build reserve
	if build_ingots <= 0:
		return
	if _push_item(coordinate, Database.item(cell.machine.definition.storage_item)):
		build_ingots -= 1

func _tick_assembler(coordinate: Vector2i, cell: Cell, scaled_delta: float) -> void:
	var machine := cell.machine
	if machine.output_count == 0 and _assembler_ready(machine):
		machine.progress += scaled_delta
		if machine.progress >= machine.recipe.craft_time:
			machine.progress = 0.0
			machine.output_loadout = _build_loadout(machine)
			machine.output_count = 1
			machine.inputs.clear()
	if machine.output_count > 0 and _push_item(coordinate, Database.item(&"robot"), machine.output_loadout):
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
	var target: Cell = cells.get(target_coordinate)
	if target == null:
		return false
	if not _accepts_from(target, target_coordinate, from_coordinate) or not _has_room_for(target, item.definition):
		return false
	if target.kind == CellKind.MACHINE:
		_deposit_into_machine(target.machine, item)
	else:
		item.offset = 0.0
		target.item = item
	return true

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

func _tick_routers() -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind != CellKind.ROUTER or cell.item == null:
			continue
		if cell.router_kind == RouterKind.SPLITTER:
			_splitter_push(coordinate, cell)
		else:
			_move_item_out(coordinate, cell, cell.output_direction)

# send the item out the next free side (not the input), cycling for an even split
func _splitter_push(coordinate: Vector2i, cell: Cell) -> void:
	for step in range(DIRECTIONS.size()):
		var direction := (cell.round_robin_index + step) % DIRECTIONS.size()
		if direction == cell.input_direction:
			continue
		if _move_item_out(coordinate, cell, direction):
			cell.round_robin_index = (direction + 1) % DIRECTIONS.size()
			return

func _move_item_out(coordinate: Vector2i, cell: Cell, direction: int) -> bool:
	if _deliver_to(coordinate, coordinate + DIRECTIONS[direction], cell.item):
		cell.item = null
		return true
	return false

# --- connection rules (shared by belts and machines) ---

# can this cell take an item coming from that spot
func _accepts_from(cell: Cell, cell_coordinate: Vector2i, from_coordinate: Vector2i) -> bool:
	match cell.kind:
		CellKind.BELT:
			return cell_coordinate + DIRECTIONS[cell.input_direction] == from_coordinate
		CellKind.MACHINE:
			return cell_coordinate + DIRECTIONS[cell.input_direction] == from_coordinate \
				and cell.machine.definition.kind != MachineDef.Kind.SOURCE
		CellKind.ROUTER:
			if cell.router_kind == RouterKind.SPLITTER:
				return cell_coordinate + DIRECTIONS[cell.input_direction] == from_coordinate
			# a merger takes from any side except its output
			var from_direction := _direction_index(from_coordinate - cell_coordinate)
			return from_direction != -1 and from_direction != cell.output_direction
	return false

# does the cell over there feed into this one
func _outputs_into(source_coordinate: Vector2i, target_coordinate: Vector2i) -> bool:
	var source: Cell = cells.get(source_coordinate)
	if source == null:
		return false
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
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_place_at(_world_to_cell(get_global_mouse_position()))
			else:
				has_chain_anchor = false               # done dragging
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_remove_cell(_world_to_cell(get_global_mouse_position()))
	elif event is InputEventMouseMotion:
		if event.button_mask & MOUSE_BUTTON_MASK_LEFT and selected_tool == Tool.BELT:
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
	if cells.has(coordinate) or not _afford(cost):
		return
	var cell := _new_machine_cell(machine_id)
	if recipe_override != null:
		cell.machine.recipe = recipe_override
	cells[coordinate] = cell
	build_ingots -= cost
	for direction in range(DIRECTIONS.size()):       # let nearby belts hook onto it
		_snap_belt(coordinate + DIRECTIONS[direction])

func _new_machine_cell(machine_id: StringName) -> Cell:
	var cell := Cell.new()
	cell.kind = CellKind.MACHINE
	cell.machine_id = machine_id
	cell.input_direction = _opposite_direction(placement_direction)
	cell.output_direction = placement_direction
	cell.machine = Machine.new()
	cell.machine.definition = Database.machine(machine_id)
	cell.machine.recipe = cell.machine.definition.recipe
	return cell

func _remove_cell(coordinate: Vector2i) -> void:
	var cell: Cell = cells.get(coordinate)
	if cell == null:
		return
	if cell.kind == CellKind.MACHINE and _is_prefab(cell.machine.definition.kind):
		return  # the depo and shuttle stay put
	build_ingots = min(build_ingots + _cost_of_cell(cell), BUILD_INGOT_CAP)  # refund
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
		if _accepts_from(neighbor, neighbor_coordinate, coordinate):
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
	return target != null and _accepts_from(target, target_coordinate, coordinate)

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
	_draw_hud()

func _draw_placeholders() -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		match cell.kind:
			CellKind.BELT:
				_draw_belt_placeholder(_cell_rect(coordinate), cell.input_direction, cell.output_direction, 1.0)
			CellKind.MACHINE:
				_draw_machine_shape(_cell_rect(coordinate), cell.machine.definition.color, cell.input_direction, cell.output_direction, 1.0)
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
			_draw_item_shape(_cell_center(coordinate), cell.item.definition.shape, cell.item.definition.color)

func _draw_machine_ui_layer() -> void:
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.MACHINE:
			_draw_machine_ui(coordinate, cell)

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

func _draw_machine_ui(coordinate: Vector2i, cell: Cell) -> void:
	var definition := cell.machine.definition
	var rect := _cell_rect(coordinate)
	var font := ThemeDB.fallback_font
	draw_string(font, rect.position + Vector2(2, 12), _machine_label(cell.machine), 0, -1, 9, Color(1, 1, 1, 0.95))
	match definition.kind:
		MachineDef.Kind.CRAFTER, MachineDef.Kind.ASSEMBLER:
			var fraction := clampf(cell.machine.progress / cell.machine.recipe.craft_time, 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 5), Vector2((rect.size.x - 4) * fraction, 3)), Color(0.5, 0.9, 0.5))
		MachineDef.Kind.STORAGE:
			draw_string(font, rect.position + Vector2(2, rect.size.y - 4), str(build_ingots), 0, -1, 9, Color(1, 1, 1, 0.9))
		MachineDef.Kind.SOURCE:
			draw_string(font, rect.position + Vector2(2, rect.size.y - 4), str(cell.machine.stored), 0, -1, 9, Color(1, 1, 1, 0.9))
		MachineDef.Kind.SHUTTLE:
			draw_string(font, rect.position + Vector2(2, rect.size.y - 4), str(Run.pending_robots.size()), 0, -1, 9, Color(1, 1, 1, 0.9))

func _machine_label(machine: Machine) -> String:
	# a crafter shows what it's making; everything else shows its own name
	if machine.definition.kind == MachineDef.Kind.CRAFTER and not machine.definition.recipes.is_empty():
		return Database.item(machine.recipe.output_id).display_name
	return machine.definition.display_name

func _draw_machine_shape(rect: Rect2, color: Color, input_direction: int, output_direction: int, alpha: float) -> void:
	var fill := color
	fill.a = alpha
	draw_rect(rect, fill)
	draw_rect(rect, Color(0, 0, 0, 0.5 * alpha), false, 1.0)
	var center := rect.position + rect.size * 0.5
	var output_vector := Vector2(DIRECTIONS[output_direction])
	var output_color := Color(0.5, 0.9, 0.5, alpha)
	var head := center + output_vector * (CELL_SIZE * 0.5 - 3.0)
	var perpendicular := Vector2(-output_vector.y, output_vector.x)
	draw_line(center, head, output_color, 2.0)
	draw_line(head, head - output_vector * 4.0 + perpendicular * 3.0, output_color, 2.0)
	draw_line(head, head - output_vector * 4.0 - perpendicular * 3.0, output_color, 2.0)
	var input_vector := Vector2(DIRECTIONS[input_direction])
	draw_line(center, center + input_vector * (CELL_SIZE * 0.5 - 3.0), Color(0.7, 0.7, 0.7, alpha * 0.8), 1.5)

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
	if cells.has(hovered_coordinate):
		draw_rect(_cell_rect(hovered_coordinate), Color(1, 0.3, 0.3, 0.25))  # can't place here
		return
	var rect := _cell_rect(hovered_coordinate)
	var input_direction := _opposite_direction(placement_direction)
	if selected_tool == Tool.BELT:
		_draw_belt_placeholder(rect, input_direction, placement_direction, 0.5)
	elif selected_tool == Tool.SPLITTER:
		_draw_router_shape(rect, RouterKind.SPLITTER, input_direction, placement_direction, 0.5)
	elif selected_tool == Tool.MERGER:
		_draw_router_shape(rect, RouterKind.MERGER, input_direction, placement_direction, 0.5)
	else:
		var definition := Database.machine(TOOL_MACHINE[selected_tool])
		var label := definition.display_name
		if selected_tool == Tool.CRAFTER:
			label = Database.item(_selected_crafter_recipe().output_id).display_name
		_draw_machine_shape(rect, definition.color, input_direction, placement_direction, 0.5)
		draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, 12), label, 0, -1, 9, Color(1, 1, 1, 0.5))

func _draw_hud() -> void:
	var depo_scrap := 0
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.MACHINE and cell.machine.definition.kind == MachineDef.Kind.SOURCE:
			depo_scrap += cell.machine.stored
	var tool_label: String = TOOL_NAMES[selected_tool]
	if selected_tool == Tool.CRAFTER:
		tool_label = "Crafter (%s)" % Database.item(_selected_crafter_recipe().output_id).display_name
	var hud_text := "Tool: %s   Speed: %sx   Build ingots: %d   Depo scrap: %d   Robots: %d   [B]elt [F]orge [K]bank [C]rafter [A]ssemble [S]plit [M]erge  [LMB] place  [RMB] remove  [R] rotate  [1/2/3] speed" % [
		tool_label, str(Sim.speed), build_ingots, depo_scrap, Run.pending_robots.size()]
	draw_string(ThemeDB.fallback_font, Vector2(10, 22), hud_text, 0, -1, 14, Color(1, 1, 1, 0.9))
