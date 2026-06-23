class_name Splitter extends RefCounted
## A splitter's output choice. Strict round-robin: it waits on a briefly busy output so it keeps its
## turn, but skips a genuinely full one so the line keeps moving.

# round-robin that never skips a usable output. it sends to the next output in rotation; if that
# output is just briefly busy (a belt/router mid-transit) it waits so the output keeps its turn,
# but a genuinely full one (a backed-up machine, or busy past the patience) is skipped to keep moving
static func next_exit(factory: Factory, coordinate: Vector2i, cell: Cell, scaled_delta: float) -> int:
	var preferred := preferred_output(cell)
	if preferred == -1:
		return -1
	if factory._can_deliver(coordinate, coordinate + Factory.DIRECTIONS[preferred], cell.item.definition):
		cell.stall_time = 0.0
		return preferred
	if output_briefly_busy(factory, coordinate, coordinate + Factory.DIRECTIONS[preferred]):
		cell.stall_time += scaled_delta
		if cell.stall_time < Factory.SPLITTER_PATIENCE:
			return -1  # wait for it to clear instead of skipping a working output
	for step in range(Factory.DIRECTIONS.size()):
		var direction := (cell.round_robin_index + step) % Factory.DIRECTIONS.size()
		if direction == cell.input_direction or direction == preferred:
			continue
		if factory._can_deliver(coordinate, coordinate + Factory.DIRECTIONS[direction], cell.item.definition):
			cell.stall_time = 0.0
			return direction
	return -1

# an output that's ours topologically but just holds an item right now -- a belt/router passing its
# own stream, which clears on its own. a full machine is not "briefly" busy, so it doesn't count
static func output_briefly_busy(factory: Factory, from_coordinate: Vector2i, target_coordinate: Vector2i) -> bool:
	var target: Cell = factory.cells.get(target_coordinate)
	if target == null or (target.kind != Factory.CellKind.BELT and target.kind != Factory.CellKind.ROUTER):
		return false
	return target.item != null and factory._accepts_from(target, target_coordinate, from_coordinate)

# the output the rotation currently points at (the first side that isn't the input)
static func preferred_output(cell: Cell) -> int:
	for step in range(Factory.DIRECTIONS.size()):
		var direction := (cell.round_robin_index + step) % Factory.DIRECTIONS.size()
		if direction != cell.input_direction:
			return direction
	return -1
