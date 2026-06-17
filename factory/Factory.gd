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

enum CellKind { BELT, MACHINE }
enum Tool { BELT, FORGE, BANK }

const TOOL_NAMES := ["Belt", "Forge", "Bank"]
const TOOL_MACHINE := { Tool.FORGE: &"forge", Tool.BANK: &"bank" }

class Item:
	var definition: ItemDef
	var offset: float = 0.0  # 0 at the input edge, 1 at the output edge
	func _init(item_definition: ItemDef) -> void:
		definition = item_definition

class Machine:
	var definition: MachineDef
	var progress: float = 0.0
	var inputs: Dictionary = {}    # item id -> count waiting to be crafted
	var output_item: ItemDef = null
	var output_count: int = 0      # finished items waiting to leave
	var stored: int = 0            # source reservoir, or stored amount for the bank

class Cell:
	var kind: int
	var input_direction: int = 2   # side items come in from
	var output_direction: int = 0  # side items go out
	var item: Item = null          # belt: one item at a time
	var machine_id: StringName = &""
	var machine: Machine = null    # set on machine cells

var cells: Dictionary = {}  # Vector2i grid coordinate -> Cell
var depo_coordinate := Vector2i(1, 6)
var selected_tool := Tool.BELT
var placement_direction := 0   # facing used when you place something
var hovered_coordinate := Vector2i.ZERO

var belt_frames: Array[Texture2D] = []
var belt_animation_time := 0.0

# while dragging belts, each one links to the last so corners form on their own
var has_chain_anchor := false
var chain_anchor := Vector2i.ZERO

func _ready() -> void:
	_load_belt_frames()
	var depo := _new_machine_cell(&"depo")
	depo.machine.stored = DEPO_START_SCRAP
	cells[depo_coordinate] = depo

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
	if into_cell.kind == CellKind.BELT:
		into_cell.item = item
		item.offset = clamp(item.offset - 1.0, 0.0, 0.99)
	else:
		_deposit_into_machine(into_cell.machine, item.definition)
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
			MachineDef.Kind.STORAGE: _tick_storage(coordinate, cell)

func _tick_source(coordinate: Vector2i, cell: Cell) -> void:
	var machine := cell.machine
	if machine.stored <= 0:
		return
	if _push_item(coordinate, Database.item(machine.definition.source_item)):
		machine.stored -= 1

func _tick_crafter(coordinate: Vector2i, cell: Cell, scaled_delta: float) -> void:
	var machine := cell.machine
	var recipe := machine.definition.recipe
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
	var machine := cell.machine
	if machine.stored <= 0:
		return
	if _push_item(coordinate, Database.item(machine.definition.storage_item)):
		machine.stored -= 1

# drop one item on the output-side belt if it's free
func _push_item(coordinate: Vector2i, item_definition: ItemDef) -> bool:
	var cell: Cell = cells[coordinate]
	var target_coordinate: Vector2i = coordinate + DIRECTIONS[cell.output_direction]
	var target: Cell = cells.get(target_coordinate)
	if target == null or target.kind != CellKind.BELT or target.item != null:
		return false
	if not _accepts_from(target, target_coordinate, coordinate):
		return false
	target.item = Item.new(item_definition)
	return true

func _deposit_into_machine(machine: Machine, item_definition: ItemDef) -> void:
	if machine.definition.kind == MachineDef.Kind.CRAFTER:
		machine.inputs[item_definition.id] = machine.inputs.get(item_definition.id, 0) + 1
	elif machine.definition.kind == MachineDef.Kind.STORAGE:
		machine.stored += 1

func _has_recipe_inputs(machine: Machine, recipe: Recipe) -> bool:
	for input_id in recipe.inputs:
		if machine.inputs.get(input_id, 0) < recipe.inputs[input_id]:
			return false
	return true

func _consume_recipe_inputs(machine: Machine, recipe: Recipe) -> void:
	for input_id in recipe.inputs:
		machine.inputs[input_id] -= recipe.inputs[input_id]

# --- connection rules (shared by belts and machines) ---

# can this cell take an item coming from that spot
func _accepts_from(cell: Cell, cell_coordinate: Vector2i, from_coordinate: Vector2i) -> bool:
	if cell_coordinate + DIRECTIONS[cell.input_direction] != from_coordinate:
		return false
	if cell.kind == CellKind.BELT:
		return true
	return cell.machine.definition.kind != MachineDef.Kind.SOURCE

# does the cell over there feed into this one
func _outputs_into(source_coordinate: Vector2i, target_coordinate: Vector2i) -> bool:
	var source: Cell = cells.get(source_coordinate)
	if source == null:
		return false
	return source_coordinate + DIRECTIONS[source.output_direction] == target_coordinate

func _has_room_for(cell: Cell, item_definition: ItemDef) -> bool:
	if cell.kind == CellKind.BELT:
		return cell.item == null
	return _machine_accepts(cell.machine, item_definition)

func _machine_accepts(machine: Machine, item_definition: ItemDef) -> bool:
	match machine.definition.kind:
		MachineDef.Kind.CRAFTER:
			var recipe := machine.definition.recipe
			if not recipe.inputs.has(item_definition.id):
				return false
			return machine.inputs.get(item_definition.id, 0) < item_definition.stack_size
		MachineDef.Kind.STORAGE:
			if item_definition.id != machine.definition.storage_item:
				return false
			return machine.stored < machine.definition.storage_capacity
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
			KEY_R: placement_direction = (placement_direction + 1) % DIRECTIONS.size()
			KEY_1: Sim.speed = 0.5
			KEY_2: Sim.speed = 1.0
			KEY_3: Sim.speed = 2.0

func _place_at(coordinate: Vector2i) -> void:
	if selected_tool == Tool.BELT:
		has_chain_anchor = false                       # start a new run of belts
		_try_place_belt(coordinate)
	else:
		_place_machine(coordinate, TOOL_MACHINE[selected_tool])

func _try_place_belt(coordinate: Vector2i) -> void:
	if cells.has(coordinate):
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
	_snap_belt(coordinate)
	chain_anchor = coordinate
	has_chain_anchor = true

func _place_machine(coordinate: Vector2i, machine_id: StringName) -> void:
	if cells.has(coordinate):
		return
	cells[coordinate] = _new_machine_cell(machine_id)
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
	return cell

func _remove_cell(coordinate: Vector2i) -> void:
	var cell: Cell = cells.get(coordinate)
	if cell == null:
		return
	if cell.kind == CellKind.MACHINE and cell.machine.definition.kind == MachineDef.Kind.SOURCE:
		return  # the depo stays put
	cells.erase(coordinate)

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
	_draw_grid()
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.BELT:
			_draw_belt(coordinate, cell.input_direction, cell.output_direction)
		else:
			_draw_machine(coordinate, cell)
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.BELT and cell.item != null:
			_draw_item(coordinate, cell)
	_draw_placement_preview()
	_draw_hud()

func _cell_rect(coordinate: Vector2i) -> Rect2:
	return Rect2(Vector2(coordinate) * CELL_SIZE, Vector2(CELL_SIZE, CELL_SIZE))

func _draw_grid() -> void:
	var grid_color := Color(1, 1, 1, 0.06)
	for column in range(GRID_COLUMNS + 1):
		draw_line(Vector2(column * CELL_SIZE, 0), Vector2(column * CELL_SIZE, GRID_ROWS * CELL_SIZE), grid_color)
	for row in range(GRID_ROWS + 1):
		draw_line(Vector2(0, row * CELL_SIZE), Vector2(GRID_COLUMNS * CELL_SIZE, row * CELL_SIZE), grid_color)

func _draw_belt(coordinate: Vector2i, input_direction: int, output_direction: int, alpha := 1.0) -> void:
	var rect := _cell_rect(coordinate)
	var is_straight := input_direction == _opposite_direction(output_direction)
	if is_straight and not belt_frames.is_empty():
		_draw_belt_frame(rect, output_direction, alpha)
		return
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

func _draw_machine(coordinate: Vector2i, cell: Cell) -> void:
	var definition := cell.machine.definition
	var rect := _cell_rect(coordinate)
	_draw_machine_shape(rect, definition.color, definition.display_name, cell.input_direction, cell.output_direction, 1.0)
	var font := ThemeDB.fallback_font
	match definition.kind:
		MachineDef.Kind.CRAFTER:
			var fraction := clampf(cell.machine.progress / definition.recipe.craft_time, 0.0, 1.0)
			draw_rect(Rect2(rect.position + Vector2(2, rect.size.y - 5), Vector2((rect.size.x - 4) * fraction, 3)), Color(0.5, 0.9, 0.5))
		MachineDef.Kind.STORAGE:
			draw_string(font, rect.position + Vector2(2, rect.size.y - 4), str(cell.machine.stored), 0, -1, 9, Color(1, 1, 1, 0.9))
		MachineDef.Kind.SOURCE:
			draw_string(font, rect.position + Vector2(2, rect.size.y - 4), str(cell.machine.stored), 0, -1, 9, Color(1, 1, 1, 0.9))

func _draw_machine_shape(rect: Rect2, color: Color, label: String, input_direction: int, output_direction: int, alpha: float) -> void:
	var fill := color
	fill.a = alpha
	draw_rect(rect, fill)
	draw_rect(rect, Color(0, 0, 0, 0.5 * alpha), false, 1.0)
	draw_string(ThemeDB.fallback_font, rect.position + Vector2(2, 12), label, 0, -1, 9, Color(1, 1, 1, alpha))
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

func _draw_item(coordinate: Vector2i, cell: Cell) -> void:
	# item rides the path, curving through corners
	var center := _cell_center(coordinate)
	var entry := center + Vector2(DIRECTIONS[cell.input_direction]) * (CELL_SIZE * 0.5)
	var exit_point := center + Vector2(DIRECTIONS[cell.output_direction]) * (CELL_SIZE * 0.5)
	var item_position := _quadratic_bezier(entry, center, exit_point, cell.item.offset)
	var top_left := item_position - Vector2(ITEM_SIZE, ITEM_SIZE) * 0.5
	draw_rect(Rect2(top_left, Vector2(ITEM_SIZE, ITEM_SIZE)), cell.item.definition.color)

func _draw_placement_preview() -> void:
	if cells.has(hovered_coordinate):
		draw_rect(_cell_rect(hovered_coordinate), Color(1, 0.3, 0.3, 0.25))  # can't place here
		return
	var input_direction := _opposite_direction(placement_direction)
	if selected_tool == Tool.BELT:
		_draw_belt(hovered_coordinate, input_direction, placement_direction, 0.5)
	else:
		var definition := Database.machine(TOOL_MACHINE[selected_tool])
		_draw_machine_shape(_cell_rect(hovered_coordinate), definition.color, definition.display_name, input_direction, placement_direction, 0.5)

func _draw_hud() -> void:
	var depo_scrap := 0
	var banked_ingots := 0
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind != CellKind.MACHINE:
			continue
		if cell.machine.definition.kind == MachineDef.Kind.SOURCE:
			depo_scrap += cell.machine.stored
		elif cell.machine.definition.kind == MachineDef.Kind.STORAGE:
			banked_ingots += cell.machine.stored
	var hud_text := "Tool: %s   Speed: %sx   Depo scrap: %d   Banked ingots: %d   [B]elt [F]orge [K]bank  [LMB] place  [RMB] remove  [R] rotate  [1/2/3] speed" % [
		TOOL_NAMES[selected_tool], str(Sim.speed), depo_scrap, banked_ingots]
	draw_string(ThemeDB.fallback_font, Vector2(10, 22), hud_text, 0, -1, 14, Color(1, 1, 1, 0.9))
