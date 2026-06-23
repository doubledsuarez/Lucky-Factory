class_name Routers extends RefCounted
## Drives items through routers (in edge -> center -> out edge) and hands the exit choice to the
## splitter or merger logic. Splitter and Merger hold the actual routing rules.

static func advance(factory: Factory, scaled_delta: float) -> void:
	for coordinate in factory.cells.keys():
		var cell: Cell = factory.cells[coordinate]
		if cell.kind != Factory.CellKind.ROUTER:
			continue
		if cell.item == null:
			if cell.router_kind == Factory.RouterKind.MERGER:
				Merger.advance_intake(factory, coordinate, cell)
			continue
		var item: Item = cell.item
		item.offset += Factory.BELT_SPEED * scaled_delta
		if item.route_exit == -1 and item.offset >= 0.5:
			item.route_exit = choose_exit(factory, coordinate, cell, item, scaled_delta)
		if item.route_exit == -1:
			item.offset = min(item.offset, 0.5)  # no open exit yet, idle at the center
			continue
		if item.offset >= 1.0:
			if factory._deliver_to(coordinate, coordinate + Factory.DIRECTIONS[item.route_exit], item):
				if cell.router_kind == Factory.RouterKind.SPLITTER:
					cell.round_robin_index = (item.route_exit + 1) % Factory.DIRECTIONS.size()
					cell.stall_time = 0.0
				cell.item = null
			else:
				item.offset = 1.0  # exit blocked, wait at the edge
				if cell.router_kind == Factory.RouterKind.SPLITTER:
					item.route_exit = -1  # re-check next tick

static func choose_exit(factory: Factory, coordinate: Vector2i, cell: Cell, item: Item, scaled_delta: float) -> int:
	if cell.router_kind == Factory.RouterKind.MERGER:
		var exit_direction := cell.output_direction
		return exit_direction if factory._can_deliver(coordinate, coordinate + Factory.DIRECTIONS[exit_direction], item.definition) else -1
	return Splitter.next_exit(factory, coordinate, cell, scaled_delta)
