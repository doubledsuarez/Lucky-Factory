class_name FactoryRenderer extends RefCounted
## All of the factory's drawing. Factory._draw() calls draw(self); every draw command runs on the
## factory node (the canvas), so the helpers take it as the first argument.

const BLOCKED_OVERLAY := Color(1.0, 0.25, 0.25, 0.4)

static func draw(factory: Factory) -> void:
	# layers, bottom to top: placeholders, belt animation, items, machine UI
	draw_grid(factory)
	draw_placeholders(factory)
	if factory.show_animations:
		draw_belt_animations(factory)
	draw_items(factory)
	draw_machine_ui_layer(factory)
	if not factory.preview_mode:
		draw_placement_preview(factory)

static func draw_placeholders(factory: Factory) -> void:
	for coordinate in factory.cells.keys():
		var cell: Cell = factory.cells[coordinate]
		match cell.kind:
			Factory.CellKind.BELT:
				draw_belt_placeholder(factory, cell_rect(coordinate), cell.input_direction, cell.output_direction, 1.0)
			Factory.CellKind.MACHINE:
				if cell.machine_origin == coordinate:
					draw_machine_body(factory, cell.machine, 1.0)
			Factory.CellKind.ROUTER:
				draw_router_shape(factory, cell_rect(coordinate), cell.router_kind, cell.input_direction, cell.output_direction, 1.0)

static func draw_belt_animations(factory: Factory) -> void:
	if factory.belt_frames.is_empty():
		return
	for coordinate in factory.cells.keys():
		var cell: Cell = factory.cells[coordinate]
		if cell.kind == Factory.CellKind.BELT and cell.input_direction == factory._opposite_direction(cell.output_direction):
			draw_belt_frame(factory, cell_rect(coordinate), cell.output_direction, 1.0)

static func draw_items(factory: Factory) -> void:
	for coordinate in factory.cells.keys():
		var cell: Cell = factory.cells[coordinate]
		if cell.item == null:
			continue
		if cell.kind == Factory.CellKind.BELT:
			draw_item(factory, coordinate, cell)
		elif cell.kind == Factory.CellKind.ROUTER:
			draw_router_item(factory, coordinate, cell)

static func draw_machine_ui_layer(factory: Factory) -> void:
	for coordinate in factory.cells.keys():
		var cell: Cell = factory.cells[coordinate]
		if cell.kind == Factory.CellKind.MACHINE and cell.machine_origin == coordinate:
			draw_machine_ui(factory, cell)

static func cell_rect(coordinate: Vector2i) -> Rect2:
	return Rect2(Vector2(coordinate) * Factory.CELL_SIZE, Vector2(Factory.CELL_SIZE, Factory.CELL_SIZE))

static func cell_center(coordinate: Vector2i) -> Vector2:
	return Vector2(coordinate) * Factory.CELL_SIZE + Vector2(Factory.CELL_SIZE, Factory.CELL_SIZE) * 0.5

static func quadratic_bezier(start: Vector2, control: Vector2, end: Vector2, t: float) -> Vector2:
	var inverse := 1.0 - t
	return inverse * inverse * start + 2.0 * inverse * t * control + t * t * end

static func draw_grid(factory: Factory) -> void:
	var grid_color := Color(1, 1, 1, 0.06)
	for column in range(Factory.GRID_COLUMNS + 1):
		factory.draw_line(Vector2(column * Factory.CELL_SIZE, 0), Vector2(column * Factory.CELL_SIZE, Factory.GRID_ROWS * Factory.CELL_SIZE), grid_color)
	for row in range(Factory.GRID_ROWS + 1):
		factory.draw_line(Vector2(0, row * Factory.CELL_SIZE), Vector2(Factory.GRID_COLUMNS * Factory.CELL_SIZE, row * Factory.CELL_SIZE), grid_color)

static func draw_belt_placeholder(factory: Factory, rect: Rect2, input_direction: int, output_direction: int, alpha := 1.0) -> void:
	factory.draw_rect(rect, Color(0.16, 0.16, 0.18, alpha))
	factory.draw_rect(rect, Color(0, 0, 0, 0.4 * alpha), false, 1.0)
	var center := rect.position + rect.size * 0.5
	var input_vector := Vector2(Factory.DIRECTIONS[input_direction])
	var output_vector := Vector2(Factory.DIRECTIONS[output_direction])
	var arrow_color := Color(0.5, 0.9, 0.5, alpha)
	# arrow runs from the in side, through the center, to the out side
	var tail := center + input_vector * 8.0
	var head := center + output_vector * 8.0
	factory.draw_line(tail, center, arrow_color, 2.0)
	factory.draw_line(center, head, arrow_color, 2.0)
	var perpendicular := Vector2(-output_vector.y, output_vector.x)
	factory.draw_line(head, head - output_vector * 5.0 + perpendicular * 4.0, arrow_color, 2.0)
	factory.draw_line(head, head - output_vector * 5.0 - perpendicular * 4.0, arrow_color, 2.0)

static func draw_belt_frame(factory: Factory, rect: Rect2, output_direction: int, alpha: float) -> void:
	var frame := int(factory.belt_animation_time * Factory.BELT_FRAMES_PER_SECOND) % factory.belt_frames.size()
	var center := rect.position + rect.size * 0.5
	# the art scrolls up by default, so add a quarter turn to line it up with the output direction
	factory.draw_set_transform(center, (output_direction + 1) * PI * 0.5, Vector2.ONE)
	factory.draw_texture_rect(factory.belt_frames[frame], Rect2(-rect.size * 0.5, rect.size), false, Color(1, 1, 1, alpha))
	factory.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func machine_rect(machine: Machine) -> Rect2:
	return Rect2(Vector2(machine.origin) * Factory.CELL_SIZE, Vector2(machine.footprint) * Factory.CELL_SIZE)

static func draw_machine_ui(factory: Factory, cell: Cell) -> void:
	var machine := cell.machine
	var rect := machine_rect(machine)
	var font := ThemeDB.fallback_font
	factory.draw_string(font, rect.position + Vector2(Factory.LABEL_INSET, Factory.LABEL_FONT_SIZE), machine_label(machine), 0, -1, Factory.LABEL_FONT_SIZE, Color(1, 1, 1, 0.95))
	match machine.definition.kind:
		MachineDef.Kind.CRAFTER, MachineDef.Kind.ASSEMBLER:
			if machine.recipe != null:
				var fraction := clampf(machine.progress / machine.recipe.craft_time, 0.0, 1.0)
				var bar_height := Factory.CELL_SIZE * 0.08
				factory.draw_rect(Rect2(rect.position + Vector2(Factory.LABEL_INSET, rect.size.y - bar_height - 2.0), Vector2((rect.size.x - Factory.LABEL_INSET * 2.0) * fraction, bar_height)), Color(0.5, 0.9, 0.5))
		MachineDef.Kind.STORAGE:
			factory.draw_string(font, rect.position + Vector2(Factory.LABEL_INSET, rect.size.y - Factory.LABEL_INSET), str(factory.build_ingots), 0, -1, Factory.LABEL_FONT_SIZE, Color(1, 1, 1, 0.9))
		MachineDef.Kind.SOURCE:
			factory.draw_string(font, rect.position + Vector2(Factory.LABEL_INSET, rect.size.y - Factory.LABEL_INSET), str(machine.stored), 0, -1, Factory.LABEL_FONT_SIZE, Color(1, 1, 1, 0.9))
		MachineDef.Kind.SHUTTLE:
			factory.draw_string(font, rect.position + Vector2(Factory.LABEL_INSET, rect.size.y - Factory.LABEL_INSET), str(Run.shuttle_robots.size()), 0, -1, Factory.LABEL_FONT_SIZE, Color(1, 1, 1, 0.9))

static func machine_label(machine: Machine) -> String:
	# a configured crafter shows what it's making; an empty one says so
	if machine.definition.kind == MachineDef.Kind.CRAFTER and not machine.definition.recipes.is_empty():
		return Database.item(machine.recipe.output_id).display_name if machine.recipe != null else "Crafter (empty)"
	return machine.definition.display_name

static func draw_machine_body(factory: Factory, machine: Machine, alpha: float) -> void:
	var rect := machine_rect(machine)
	var fill := machine.definition.color
	fill.a = alpha
	factory.draw_rect(rect, fill)
	factory.draw_rect(rect, Color(0, 0, 0, 0.5 * alpha), false, 1.0)
	for port in machine.world_ports:
		draw_port(factory, port.coord, port.side, port.role, alpha)

static func draw_port(factory: Factory, coordinate: Vector2i, side: int, role: int, alpha: float) -> void:
	var center := cell_center(coordinate)
	if role == MachinePort.Role.OUTPUT:
		draw_side_arrow(factory, center, side, Color(0.5, 0.9, 0.5, alpha))
	else:
		factory.draw_line(center, center + Vector2(Factory.DIRECTIONS[side]) * (Factory.CELL_SIZE * 0.5 - 3.0), Color(0.7, 0.7, 0.7, alpha * 0.8), 1.5)

static func draw_router_shape(factory: Factory, rect: Rect2, router_kind: int, input_direction: int, output_direction: int, alpha: float) -> void:
	var fill := router_color(router_kind)
	fill.a = alpha
	factory.draw_rect(rect, fill)
	factory.draw_rect(rect, Color(0, 0, 0, 0.5 * alpha), false, 1.0)
	var label := "SPL" if router_kind == Factory.RouterKind.SPLITTER else "MRG"
	factory.draw_string(ThemeDB.fallback_font, rect.position + Vector2(Factory.LABEL_INSET, Factory.LABEL_FONT_SIZE), label, 0, -1, Factory.LABEL_FONT_SIZE, Color(1, 1, 1, alpha))
	var center := rect.position + rect.size * 0.5
	for direction in range(Factory.DIRECTIONS.size()):
		var is_output := (router_kind == Factory.RouterKind.SPLITTER and direction != input_direction) \
			or (router_kind == Factory.RouterKind.MERGER and direction == output_direction)
		if is_output:
			draw_side_arrow(factory, center, direction, Color(0.5, 0.9, 0.5, alpha))
		else:
			factory.draw_line(center, center + Vector2(Factory.DIRECTIONS[direction]) * (Factory.CELL_SIZE * 0.5 - 3.0), Color(0.7, 0.7, 0.7, alpha * 0.8), 1.5)

static func draw_side_arrow(factory: Factory, center: Vector2, direction: int, color: Color) -> void:
	var vector := Vector2(Factory.DIRECTIONS[direction])
	var head := center + vector * (Factory.CELL_SIZE * 0.5 - 3.0)
	var perpendicular := Vector2(-vector.y, vector.x)
	factory.draw_line(center, head, color, 2.0)
	factory.draw_line(head, head - vector * 4.0 + perpendicular * 3.0, color, 2.0)
	factory.draw_line(head, head - vector * 4.0 - perpendicular * 3.0, color, 2.0)

static func router_color(router_kind: int) -> Color:
	return Color(0.25, 0.45, 0.45) if router_kind == Factory.RouterKind.SPLITTER else Color(0.45, 0.30, 0.45)

static func draw_item(factory: Factory, coordinate: Vector2i, cell: Cell) -> void:
	# item rides the path, curving through corners
	var center := cell_center(coordinate)
	var entry := center + Vector2(Factory.DIRECTIONS[cell.input_direction]) * (Factory.CELL_SIZE * 0.5)
	var exit_point := center + Vector2(Factory.DIRECTIONS[cell.output_direction]) * (Factory.CELL_SIZE * 0.5)
	var item_position := quadratic_bezier(entry, center, exit_point, cell.item.offset)
	draw_item_shape(factory, item_position, cell.item.definition.shape, cell.item.definition.color)

static func draw_router_item(factory: Factory, coordinate: Vector2i, cell: Cell) -> void:
	# first half: in edge -> center; second half: center -> out edge
	var item := cell.item
	var center := cell_center(coordinate)
	var position := center
	if item.offset < 0.5:
		var entry := center + Vector2(Factory.DIRECTIONS[item.route_entry]) * (Factory.CELL_SIZE * 0.5)
		position = entry.lerp(center, item.offset / 0.5)
	elif item.route_exit != -1:
		var exit_point := center + Vector2(Factory.DIRECTIONS[item.route_exit]) * (Factory.CELL_SIZE * 0.5)
		position = center.lerp(exit_point, (item.offset - 0.5) / 0.5)
	draw_item_shape(factory, position, item.definition.shape, item.definition.color)

static func draw_item_shape(factory: Factory, center: Vector2, shape: ItemDef.Shape, color: Color) -> void:
	if shape == ItemDef.Shape.CIRCLE:
		factory.draw_circle(center, Factory.ITEM_SIZE * 0.5, color)
	else:
		factory.draw_colored_polygon(item_polygon(shape, center), color)

static func item_polygon(shape: ItemDef.Shape, center: Vector2) -> PackedVector2Array:
	var half := Factory.ITEM_SIZE * 0.5
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

static func draw_placement_preview(factory: Factory) -> void:
	var rect := cell_rect(factory.hovered_coordinate)
	var input_direction := factory._opposite_direction(factory.placement_direction)
	match factory.selected_tool:
		Factory.Tool.BELT:
			draw_belt_placeholder(factory, rect, input_direction, factory.placement_direction, 0.5)
			if not can_place_single(factory, factory.hovered_coordinate, Factory.BELT_COST):
				factory.draw_rect(rect, BLOCKED_OVERLAY)
		Factory.Tool.SPLITTER:
			draw_router_shape(factory, rect, Factory.RouterKind.SPLITTER, input_direction, factory.placement_direction, 0.5)
			if not can_place_single(factory, factory.hovered_coordinate, Factory.SPLITTER_COST):
				factory.draw_rect(rect, BLOCKED_OVERLAY)
		Factory.Tool.MERGER:
			draw_router_shape(factory, rect, Factory.RouterKind.MERGER, input_direction, factory.placement_direction, 0.5)
			if not can_place_single(factory, factory.hovered_coordinate, Factory.MERGER_COST):
				factory.draw_rect(rect, BLOCKED_OVERLAY)
		_:
			draw_machine_preview(factory, Factory.TOOL_MACHINE[factory.selected_tool])

static func cell_in_bounds(coordinate: Vector2i) -> bool:
	return coordinate.x >= 0 and coordinate.y >= 0 and coordinate.x < Factory.GRID_COLUMNS and coordinate.y < Factory.GRID_ROWS

static func can_place_single(factory: Factory, coordinate: Vector2i, cost: int) -> bool:
	return cell_in_bounds(coordinate) and not factory.cells.has(coordinate) and factory._afford(cost)

static func draw_machine_preview(factory: Factory, machine_id: StringName) -> void:
	var def: MachineDef = Database.machine(machine_id)
	var blocked := not factory._machine_fits(factory.hovered_coordinate, def, factory.placement_direction) or not factory._afford(def.build_cost)
	for offset in factory._footprint_offsets(def, factory.placement_direction):
		var rect := cell_rect(factory.hovered_coordinate + offset)
		var fill := def.color
		fill.a = 0.4
		factory.draw_rect(rect, fill)
		if blocked:
			factory.draw_rect(rect, BLOCKED_OVERLAY)
	for port in factory._world_ports(def, factory.hovered_coordinate, factory.placement_direction):
		draw_port(factory, port.coord, port.side, port.role, 0.7)
	factory.draw_string(ThemeDB.fallback_font, cell_rect(factory.hovered_coordinate).position + Vector2(Factory.LABEL_INSET, Factory.LABEL_FONT_SIZE), def.display_name, 0, -1, Factory.LABEL_FONT_SIZE, Color(1, 1, 1, 0.7))
