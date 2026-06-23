class_name Merger extends RefCounted
## A merger's intake: hold the current input side while it keeps feeding, and only rotate to the
## next ready side once the current one runs dry. The rotation gives every input a fair turn.

static func advance_intake(factory: Factory, coordinate: Vector2i, cell: Cell) -> void:
	if cell.round_robin_index != cell.output_direction and input_ready(factory, coordinate, cell.round_robin_index):
		return  # keep accepting from this side; don't thrash the selection while an item is arriving
	for step in range(1, Factory.DIRECTIONS.size() + 1):
		var side := (cell.round_robin_index + step) % Factory.DIRECTIONS.size()
		if side != cell.output_direction and input_ready(factory, coordinate, side):
			cell.round_robin_index = side
			return

static func input_ready(factory: Factory, coordinate: Vector2i, side: int) -> bool:
	var source_coordinate: Vector2i = coordinate + Factory.DIRECTIONS[side]
	var source: Cell = factory.cells.get(source_coordinate)
	if source == null or not factory._outputs_into(source_coordinate, coordinate):
		return false
	match source.kind:
		Factory.CellKind.BELT:
			return source.item != null
		Factory.CellKind.ROUTER:
			# a feeding splitter only commits its exit once we open this side, so treat it as ready when
			# its item is aimed here OR hasn't picked an exit yet -- otherwise the two wait on each other
			if source.item == null:
				return false
			var toward := factory._direction_index(coordinate - source_coordinate)
			return source.item.route_exit == toward or source.item.route_exit == -1
		Factory.CellKind.MACHINE:
			return factory._machine_can_output(source.machine)
	return false
