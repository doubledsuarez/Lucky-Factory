class_name Factory extends Node2D
## The factory floor: place belts and machines and route scrap through them.
## Belts and machines have an input side and an output side, so items only flow the way they face.

# tile size in world pixels -- the one knob; everything below scales off it (belt art is authored at 64)
const CELL_SIZE := 64
const ITEM_SIZE := CELL_SIZE * 0.45              # item drawn size, kept proportional to the cell
const BELT_SPEED := 1.0  # cells per second (60 a minute at tier 1). Sim.speed scales it.
# where a stopped item sits: right at the edge, still on the belt
const EDGE_REST_OFFSET := 1.0 - (ITEM_SIZE * 0.5) / CELL_SIZE
const LABEL_FONT_SIZE := CELL_SIZE * 28 / 100    # ~17 at 64; scales with the cell
const LABEL_INSET := CELL_SIZE * 0.1             # corner padding for in-cell text
const DIRECTIONS := [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]
const GRID_COLUMNS := 40
const GRID_ROWS := 22
const DEPO_START_SCRAP := 1000
const BELT_FRAMES_PER_SECOND := 8.0
const STARTING_BUILD_INGOTS := 120
const BELT_COST := 5
const SPLITTER_COST := 15
const MERGER_COST := 15
# how long a splitter waits on a busy belt/router output before skipping it (one cell takes 1s to cross)
const SPLITTER_PATIENCE := 1.2
const ZOOM_MIN := 0.4   # zoomed out enough to see the whole floor
const ZOOM_MAX := 1.5   # 1.0 is native belt pixels
const ZOOM_STEP := 0.1
const DEFAULT_ZOOM := 0.5
const PAN_MARGIN_CELLS := 5  # how far past the floor the view may scroll
const WAVE_BUILD_TIME := 1800.0

enum CellKind { BELT, MACHINE, ROUTER }
enum RouterKind { SPLITTER, MERGER }
enum Tool { BELT, FORGE, BANK, CRAFTER, ASSEMBLER, SPLITTER, MERGER }

const TOOL_MACHINE := { Tool.FORGE: &"t1_forge", Tool.BANK: &"storage", Tool.CRAFTER: &"t1_crafter", Tool.ASSEMBLER: &"t1_assembler" }

var cells: Dictionary = {}  # Vector2i grid coordinate -> Cell
var depo_coordinate := Vector2i(1, 10)
# five 2x2 portals stacked down the right edge; locked ones show greyed until unlocked
const PORTAL_COLUMN := GRID_COLUMNS - 2
const PORTAL_TOP := 2
const PORTAL_SPACING := 4
const PORTAL_LAYOUT := [&"yellow", &"red", &"blue", &"green", &"orange"]  # top to bottom; blue centered
var build_ingots := STARTING_BUILD_INGOTS
var selected_tool := Tool.BELT
var placement_direction := 0   # facing used when you place something
var hovered_coordinate := Vector2i.ZERO

var belt_frames: Array[Texture2D] = []
var belt_animation_time := 0.0
@export var show_animations := true   # turn off to see plain placeholders for debugging

@onready var camera: Camera2D = $Camera2D
@onready var hud: Control = $HudLayer/Hud

# while dragging belts, each one links to the last so corners form on their own
var has_chain_anchor := false
var chain_anchor := Vector2i.ZERO

# middle mouse: drag to pan, or click (no drag) to pick the part under the cursor
var panning := false
var pan_drag_distance := 0.0

var build_time_left := WAVE_BUILD_TIME
var launch_armed := false
var current_wave := 1
var played_seconds := 0.0
var pause_menu: PauseMenu = null
var preview_mode := false        # menu backdrop: render a save, no sim, no saving, no input
var preview_snapshot := {}
var preview_bounds := Rect2()    # world-space extent of the placed content, for the menu camera

func _ready() -> void:
	_load_belt_frames()
	if preview_mode:
		_setup_preview()
		return
	GameManager.battle_resolved.connect(_on_battle_resolved)
	var snapshot := GameManager.take_pending_load()
	if snapshot.is_empty():
		if GameManager.current_save_name.to_lower() == "playtest":
			Unlocks.unlock_all()    # dev save: everything available
		else:
			Unlocks.seed_new_game()
		_create_machine(depo_coordinate, &"scrap_depo", 0)
		_create_portals()
		autosave()   # stamp the new slot with its name right away
	else:
		FactorySave.restore_state(self, snapshot)
	camera.position = Vector2(GRID_COLUMNS, GRID_ROWS) * CELL_SIZE * 0.5  # center on the floor
	camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	_clamp_camera()
	hud.refresh_build_bar()   # the Hud built before unlocks were seeded, so rebuild it now

func _load_belt_frames() -> void:
	var index := 1
	while true:
		var path := "res://sprites/belts/scrap_belt_straight/Straight Belt %d.png" % index
		if not ResourceLoader.exists(path):
			break
		belt_frames.append(load(path))
		index += 1

func _setup_preview() -> void:
	$HudLayer/Hud.hide()
	$HudLayer.queue_free()   # no HUD in the menu backdrop
	if not preview_snapshot.is_empty():
		FactorySave.restore_cells(self, preview_snapshot)
	else:
		_create_machine(depo_coordinate, &"scrap_depo", 0)
		_create_portals()
	for coordinate in cells:                          # keep the sources fed so the backdrop keeps flowing
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.MACHINE and cell.machine_origin == coordinate and cell.machine.definition.kind == MachineDef.Kind.SOURCE:
			cell.machine.stored = 99999
	preview_bounds = _preview_content_bounds()
	camera.position = preview_bounds.get_center()
	camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	set_process_unhandled_input(false)

# all five portals are always placed; the tech tree decides which are active (the rest show greyed)
func _create_portals() -> void:
	for index in range(PORTAL_LAYOUT.size()):
		var color: StringName = PORTAL_LAYOUT[index]
		var origin := Vector2i(PORTAL_COLUMN, PORTAL_TOP + index * PORTAL_SPACING)
		_create_machine(origin, StringName("portal_" + color), 0)

func _preview_content_bounds() -> Rect2:
	if cells.is_empty():
		return Rect2(Vector2.ZERO, Vector2(GRID_COLUMNS, GRID_ROWS) * CELL_SIZE)
	var min_cell := Vector2i(1 << 30, 1 << 30)
	var max_cell := Vector2i(-(1 << 30), -(1 << 30))
	for coordinate in cells:
		min_cell.x = mini(min_cell.x, coordinate.x)
		min_cell.y = mini(min_cell.y, coordinate.y)
		max_cell.x = maxi(max_cell.x, coordinate.x)
		max_cell.y = maxi(max_cell.y, coordinate.y)
	return Rect2(Vector2(min_cell) * CELL_SIZE, Vector2(max_cell - min_cell + Vector2i.ONE) * CELL_SIZE)

func _process(delta: float) -> void:
	if preview_mode:
		# run the sim for ambiance, but it never saves or touches run state
		belt_animation_time += delta
		Belts.advance_items(self, delta)
		Machines.tick(self, delta)
		Routers.advance(self, delta)
		queue_redraw()
		return
	played_seconds += delta   # real time, for the save's total-played readout
	var scaled_delta := delta * Sim.speed
	belt_animation_time += scaled_delta
	build_time_left = maxf(0.0, build_time_left - scaled_delta)
	Belts.advance_items(self, scaled_delta)
	Machines.tick(self, scaled_delta)
	Routers.advance(self, scaled_delta)
	hovered_coordinate = _world_to_cell(get_global_mouse_position())
	queue_redraw()

func _enter_router(item: Item, from_coordinate: Vector2i, router_coordinate: Vector2i) -> void:
	item.offset = 0.0
	item.route_entry = _direction_index(from_coordinate - router_coordinate)
	item.route_exit = -1
	var router: Cell = cells.get(router_coordinate)
	if router != null and router.router_kind == RouterKind.MERGER:
		# just took one from this side, so rotate on so the other inputs get a fair turn next
		router.round_robin_index = (router.round_robin_index + 1) % DIRECTIONS.size()

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
			build_ingots += 1
		MachineDef.Kind.ASSEMBLER:
			machine.inputs[item.definition.slot] = item.definition
		MachineDef.Kind.PORTAL:
			if item.loadout != null and not preview_mode:
				Run.load_robot(machine.definition.portal_color, item.loadout)   # preview never touches the run

# --- shared grid helpers (used by belts, routers, and machines) ---

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
			if recipe == null or not recipe.inputs.has(item_definition.id):
				return false  # no recipe picked yet means nothing flows in
			# hold at least one full recipe's worth, plus a stack of buffer for steady crafting
			var capacity: int = maxi(int(recipe.inputs[item_definition.id]), item_definition.stack_size)
			return machine.inputs.get(item_definition.id, 0) < capacity
		MachineDef.Kind.STORAGE:
			return item_definition.id == machine.definition.storage_item
		MachineDef.Kind.ASSEMBLER:
			return item_definition.slot != ItemDef.Slot.NONE and not machine.inputs.has(item_definition.slot)
		MachineDef.Kind.PORTAL:
			# locked portals stay inactive; the preview backdrop ignores the lock so it keeps flowing
			return item_definition.id == &"robot" and (preview_mode or Unlocks.is_unlocked(machine.definition.id))
	return false

# --- placement ---

func _unhandled_input(event: InputEvent) -> void:
	# clicking or typing anything in the world cancels an armed launch
	if launch_armed and ((event is InputEventMouseButton and event.pressed) or (event is InputEventKey and event.pressed)):
		disarm_launch()
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var clicked := _world_to_cell(get_global_mouse_position())
				var existing: Cell = cells.get(clicked)
				if existing != null and existing.kind == CellKind.MACHINE and existing.machine.definition.kind == MachineDef.Kind.PORTAL:
					hud.toggle_shuttle_panel()                  # click a portal to see the manifest
				elif existing != null and existing.kind == CellKind.MACHINE and not _is_prefab(existing.machine.definition.kind):
					hud.open_machine_panel(existing.machine)    # click a placed machine to configure it
				else:
					_place_at(clicked)
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
		if event.is_action_pressed("build_belt"): selected_tool = Tool.BELT
		elif event.is_action_pressed("build_forge"): selected_tool = Tool.FORGE
		elif event.is_action_pressed("build_bank"): selected_tool = Tool.BANK
		elif event.is_action_pressed("build_crafter"): selected_tool = Tool.CRAFTER
		elif event.is_action_pressed("build_assembler"): selected_tool = Tool.ASSEMBLER
		elif event.is_action_pressed("build_splitter"): selected_tool = Tool.SPLITTER
		elif event.is_action_pressed("build_merger"): selected_tool = Tool.MERGER
		elif event.is_action_pressed("rotate"): placement_direction = (placement_direction + 1) % DIRECTIONS.size()
		elif event.is_action_pressed("speed_slow"): Sim.speed = 0.5
		elif event.is_action_pressed("speed_normal"): Sim.speed = 1.0
		elif event.is_action_pressed("speed_fast"): Sim.speed = 2.0
		elif event.is_action_pressed("pause"): _open_pause_menu()
		elif event.is_action_pressed("tech_tree"): _open_tech_tree()

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
	_place_machine(coordinate, TOOL_MACHINE[selected_tool])

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
			return  # the depo and portals stay put
		build_ingots += machine.definition.build_cost
		_return_scrap_to_depo(int(machine.inputs.get(&"scrap", 0)))  # waiting intake scrap goes home
		for machine_cell in _machine_world_cells(machine):
			cells.erase(machine_cell)
		return
	build_ingots += _cost_of_cell(cell)
	_return_scrap_to_depo(_scrap_on_cell(cell))  # scrap riding this belt or router goes home
	cells.erase(coordinate)

func _scrap_on_cell(cell: Cell) -> int:
	return 1 if cell.item != null and cell.item.definition.id == &"scrap" else 0

func _return_scrap_to_depo(count: int) -> void:
	if count <= 0:
		return
	var depo_cell: Cell = cells.get(depo_coordinate)
	if depo_cell != null and depo_cell.kind == CellKind.MACHINE:
		depo_cell.machine.stored += count

func _is_prefab(machine_kind: int) -> bool:
	return machine_kind == MachineDef.Kind.SOURCE or machine_kind == MachineDef.Kind.PORTAL

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
	if def == null:
		push_warning("Unknown machine id '%s' -- skipping (old save?)" % machine_id)
		return false
	if not _machine_fits(origin, def, orientation):
		return false
	var machine := Machine.new()
	machine.definition = def
	if recipe_override != null:
		machine.recipe = recipe_override
	elif def.recipes.is_empty():
		machine.recipe = def.recipe        # single-recipe machine like the forge
	else:
		machine.recipe = null              # pick-list machine: stays empty until configured
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
	# placed pointing our output into something that actually feeds us (a machine or splitter
	# output)? flip so we take input from it and send our output onward instead
	if not _is_output_connected(coordinate, cell) and _outputs_into(coordinate + DIRECTIONS[cell.output_direction], coordinate):
		var toward_source := cell.output_direction
		cell.input_direction = toward_source
		cell.output_direction = _opposite_direction(toward_source)
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
		&"t1_forge": selected_tool = Tool.FORGE
		&"storage": selected_tool = Tool.BANK
		&"t1_assembler": selected_tool = Tool.ASSEMBLER
		&"t1_crafter":
			selected_tool = Tool.CRAFTER

func _world_to_cell(world_position: Vector2) -> Vector2i:
	return Vector2i(floori(world_position.x / float(CELL_SIZE)), floori(world_position.y / float(CELL_SIZE)))

# --- drawing (see FactoryRenderer) ---

func _draw() -> void:
	FactoryRenderer.draw(self)

# --- HUD data (read by the Hud layer) ---

func buildables() -> Array:
	var all := [
		{ "id": &"t1_belt", "tool": Tool.BELT, "name": "T1 Belt", "hotkey": "B", "cost": BELT_COST, "color": Color(0.16, 0.16, 0.18) },
		{ "id": &"t1_forge", "tool": Tool.FORGE, "name": "T1 Forge", "hotkey": "F", "cost": Database.machine(&"t1_forge").build_cost, "color": Database.machine(&"t1_forge").color },
		{ "id": &"t1_crafter", "tool": Tool.CRAFTER, "name": "T1 Crafter", "hotkey": "C", "cost": Database.machine(&"t1_crafter").build_cost, "color": Database.machine(&"t1_crafter").color },
		{ "id": &"t1_assembler", "tool": Tool.ASSEMBLER, "name": "T1 Assembler", "hotkey": "A", "cost": Database.machine(&"t1_assembler").build_cost, "color": Database.machine(&"t1_assembler").color },
		{ "id": &"storage", "tool": Tool.BANK, "name": "Storage", "hotkey": "K", "cost": Database.machine(&"storage").build_cost, "color": Database.machine(&"storage").color },
		{ "id": &"splitter", "tool": Tool.SPLITTER, "name": "Splitter", "hotkey": "S", "cost": SPLITTER_COST, "color": FactoryRenderer.router_color(RouterKind.SPLITTER) },
		{ "id": &"merger", "tool": Tool.MERGER, "name": "Merger", "hotkey": "M", "cost": MERGER_COST, "color": FactoryRenderer.router_color(RouterKind.MERGER) },
	]
	var result := []
	for entry in all:
		if Unlocks.is_unlocked(entry.id):
			result.append(entry)
	return result

func select_build_tool(tool: int) -> void:
	selected_tool = tool
	disarm_launch()

func assign_recipe(machine: Machine, recipe: Recipe) -> void:
	machine.recipe = recipe
	machine.progress = 0.0

func hovered_machine() -> Machine:
	var cell: Cell = cells.get(hovered_coordinate)
	if cell != null and cell.kind == CellKind.MACHINE:
		return cell.machine
	return null

# display-ready breakdown of a machine's slots for the Hud inspector:
# { title, inputs:[{item, have, need}], outputs:[{item, have, need}], progress }
func machine_inspector(machine: Machine) -> Dictionary:
	var def: MachineDef = machine.definition
	var info := { "title": FactoryRenderer.machine_label(machine), "inputs": [], "outputs": [], "progress": 0.0 }
	match def.kind:
		MachineDef.Kind.SOURCE:
			info.outputs.append({ "item": def.source_item, "have": machine.stored, "need": 0 })
		MachineDef.Kind.PORTAL:
			info.inputs.append({ "item": &"robot", "have": Run.manifest(def.portal_color).size(), "need": 0 })
		MachineDef.Kind.STORAGE:
			info.inputs.append({ "item": def.storage_item, "have": 0, "need": 0 })
			info.outputs.append({ "item": def.storage_item, "have": build_ingots, "need": 0 })
		MachineDef.Kind.CRAFTER:
			if machine.recipe != null:
				for input_id in machine.recipe.inputs:
					info.inputs.append({ "item": input_id, "have": int(machine.inputs.get(input_id, 0)), "need": int(machine.recipe.inputs[input_id]) })
				info.outputs.append({ "item": machine.recipe.output_id, "have": machine.output_count, "need": 0 })
				info.progress = clampf(machine.progress / machine.recipe.craft_time, 0.0, 1.0)
		MachineDef.Kind.ASSEMBLER:
			for slot in [ItemDef.Slot.LEGS, ItemDef.Slot.TORSO, ItemDef.Slot.HEAD, ItemDef.Slot.ARMS]:
				var part: ItemDef = machine.inputs.get(slot)
				info.inputs.append({ "item": part.id if part != null else &"", "have": 1 if part != null else 0, "need": 1 })
			info.outputs.append({ "item": &"robot", "have": machine.output_count, "need": 0 })
			if machine.recipe != null:
				info.progress = clampf(machine.progress / machine.recipe.craft_time, 0.0, 1.0)
	return info

func scrap_total() -> int:
	var total := 0
	for coordinate in cells.keys():
		var cell: Cell = cells[coordinate]
		if cell.kind == CellKind.MACHINE and cell.machine_origin == coordinate and cell.machine.definition.kind == MachineDef.Kind.SOURCE:
			total += cell.machine.stored
	return total

func robot_groups() -> Array:
	var counts := {}
	var sample := {}
	var order := []
	for loadout in Run.all_robots():
		var signature: String = loadout.signature()
		if not counts.has(signature):
			counts[signature] = 0
			sample[signature] = loadout
			order.append(signature)
		counts[signature] += 1
	var result := []
	for signature in order:
		result.append({ "signature": signature, "count": counts[signature], "loadout": sample[signature] })
	return result

func time_text() -> String:
	var seconds := int(ceil(build_time_left))
	return "%d:%02d" % [seconds / 60, seconds % 60]

func arm_launch() -> void:
	launch_armed = true

func start_battle() -> void:
	launch_armed = false
	# the manifests stay loaded through the battle; they're cleared once rewards are tallied
	var army := Run.all_robots()
	print("Battle started with %d robots across the portals" % army.size())
	# placeholder until the battle exists: pretend we won with everyone surviving
	var result := BattleResult.new()
	result.won = true
	result.sent = army
	result.survivors = army.duplicate()
	GameManager.on_battle_done(result)

func _on_battle_resolved(won: bool, card_count: int) -> void:
	Run.clear_manifests()   # rewards are tallied, so empty the portals for the next round
	if won:
		hud.show_upgrade_picker(card_count)
	else:
		print("Defeated")   # defeat screen + checkpoint reload come with the round loop

# buffs take effect the moment they're unlocked; other nodes just become buildable
func apply_unlock_effect(id: StringName) -> void:
	var node_name := String(id)
	if node_name.begins_with("1000_scrap"):
		_return_scrap_to_depo(1000)
	elif node_name.begins_with("extra_time"):
		build_time_left += 60.0

func disarm_launch() -> void:
	launch_armed = false

# call at the start of a new wave to checkpoint the run to the active slot
func autosave() -> void:
	GameManager.save_snapshot(FactorySave.capture_state(self))

# --- pause menu ---

func _open_pause_menu() -> void:
	if pause_menu != null:
		return
	pause_menu = preload("res://ui/PauseMenu.tscn").instantiate() as PauseMenu
	pause_menu.resume_requested.connect(_close_pause_menu)
	pause_menu.save_requested.connect(func(): GameManager.save_snapshot(FactorySave.capture_state(self)))
	pause_menu.settings_requested.connect(func(): $HudLayer.add_child(preload("res://ui/SettingsPanel.tscn").instantiate()))
	pause_menu.tech_tree_requested.connect(_open_tech_tree)
	pause_menu.exit_requested.connect(_on_pause_exit)
	$HudLayer.add_child(pause_menu)
	get_tree().paused = true

func _open_tech_tree() -> void:
	var screen := TechTreeScreen.new()
	# if opened straight from a keypress, resume on close; if from the pause menu, stay paused
	screen.closed.connect(func(): if pause_menu == null: get_tree().paused = false)
	$HudLayer.add_child(screen)
	get_tree().paused = true

func _close_pause_menu() -> void:
	if pause_menu != null:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false

func _on_pause_exit() -> void:
	_close_pause_menu()
	GameManager.to_menu()

# save / restore live in FactorySave
