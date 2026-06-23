class_name Belts extends RefCounted
## Items moving along belts. The synced step is what keeps a packed chain, or a closed loop, advancing together.

static func advance_items(factory: Factory, scaled_delta: float) -> void:
	# every belt cell currently carrying something
	var occupied := []
	for coordinate in factory.cells.keys():
		var cell: Cell = factory.cells[coordinate]
		if cell.kind == Factory.CellKind.BELT and cell.item != null:
			occupied.append(coordinate)
	# decide which items may step forward this tick. an item may move when the cell ahead
	# accepts it and is either free or being vacated by another mover this same tick -- that
	# vacated-together rule is what keeps a full chain, or a closed loop, moving in sync.
	var can_move := {}
	for coordinate in occupied:
		can_move[coordinate] = belt_forward_open(factory, coordinate)
	var changed := true
	while changed:
		changed = false
		for coordinate in occupied:
			if not can_move[coordinate]:
				continue
			var cell: Cell = factory.cells[coordinate]
			var ahead: Vector2i = coordinate + Factory.DIRECTIONS[cell.output_direction]
			var ahead_cell: Cell = factory.cells.get(ahead)
			if ahead_cell != null and ahead_cell.kind == Factory.CellKind.BELT and ahead_cell.item != null \
				and not can_move.get(ahead, false):
				can_move[coordinate] = false
				changed = true
	# advance offsets; movers run up to the edge, blocked items rest a little further back
	for coordinate in occupied:
		var item: Item = factory.cells[coordinate].item
		if can_move[coordinate]:
			item.offset = min(item.offset + Factory.BELT_SPEED * scaled_delta, 1.0)
		else:
			item.offset = min(item.offset + Factory.BELT_SPEED * scaled_delta, Factory.EDGE_REST_OFFSET)
	# of the movers, the ones that have reached the next cell this tick
	var crossing := {}
	for coordinate in occupied:
		if can_move[coordinate] and factory.cells[coordinate].item.offset >= 1.0:
			crossing[coordinate] = true
	# a mover may only enter a belt that is empty or is itself crossing this tick
	changed = true
	while changed:
		changed = false
		for coordinate in crossing.keys():
			var cell: Cell = factory.cells[coordinate]
			var ahead: Vector2i = coordinate + Factory.DIRECTIONS[cell.output_direction]
			var ahead_cell: Cell = factory.cells.get(ahead)
			if ahead_cell != null and ahead_cell.kind == Factory.CellKind.BELT and ahead_cell.item != null \
				and not crossing.has(ahead):
				crossing.erase(coordinate)
				changed = true
	# clear the sources first, then drop each item into the cell ahead, so a packed run
	# hands off without one step clobbering the next
	var landings := {}
	for coordinate in crossing.keys():
		var cell: Cell = factory.cells[coordinate]
		var item: Item = cell.item
		var ahead: Vector2i = coordinate + Factory.DIRECTIONS[cell.output_direction]
		if factory.cells[ahead].kind == Factory.CellKind.BELT:
			cell.item = null
			landings[ahead] = item
		else:
			hand_off(factory, item, coordinate, ahead)  # machine or router intake handles itself
	for target in landings.keys():
		var item: Item = landings[target]
		item.offset = clamp(item.offset - 1.0, 0.0, 0.99)
		factory.cells[target].item = item

# is the cell ahead of this belt able to take its item (ignoring belt occupancy, which the
# mover pass resolves) -- machines and routers report their real capacity here
static func belt_forward_open(factory: Factory, coordinate: Vector2i) -> bool:
	var cell: Cell = factory.cells[coordinate]
	var ahead: Vector2i = coordinate + Factory.DIRECTIONS[cell.output_direction]
	var ahead_cell: Cell = factory.cells.get(ahead)
	if ahead_cell == null:
		return false
	if ahead_cell.kind == Factory.CellKind.BELT:
		return factory._accepts_from(ahead_cell, ahead, coordinate)
	return factory._can_deliver(coordinate, ahead, cell.item.definition)

static func hand_off(factory: Factory, item: Item, from_coordinate: Vector2i, into_coordinate: Vector2i) -> void:
	var into_cell: Cell = factory.cells[into_coordinate]
	if into_cell.kind == Factory.CellKind.MACHINE:
		factory._deposit_into_machine(into_cell.machine, item)
	elif into_cell.kind == Factory.CellKind.ROUTER:
		factory._enter_router(item, from_coordinate, into_coordinate)
		into_cell.item = item
	else:
		item.offset = clamp(item.offset - 1.0, 0.0, 0.99)
		into_cell.item = item
	factory.cells[from_coordinate].item = null
