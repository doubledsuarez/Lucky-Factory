class_name TechTreeScreen extends Control
## View-only tech tree, opened from the pause menu. Left-to-right, tidy tree layout, with fog of war:
## unlocked nodes show fully, the next reachable nodes show as black shadows, the rest stay hidden.

signal closed

const COLUMN_WIDTH := 210.0
const ROW_HEIGHT := 60.0
const NODE_SIZE := Vector2(160, 40)
const ORIGIN := Vector2(70, 110)
const ZOOM_MIN := 0.5    # zoomed out to 50% -- see twice as much
const ZOOM_MAX := 1.0
const ZOOM_STEP := 0.1

var _positions := {}     # node id -> layout position (before zoom/pan)
var _zoom := 0.6
var _pan := Vector2.ZERO
var _next_row := 0.0
var _dragging := false
var _node_style := StyleBoxFlat.new()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layout()
	var title := Label.new()
	title.text = "Tech Tree"
	title.add_theme_font_size_override("font_size", 22)
	title.position = Vector2(16, 14)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.position = Vector2(16, 48)
	back.pressed.connect(_close)
	add_child(back)
	queue_redraw()

# tidy tree: leaves get sequential rows, a parent sits centered on its children
func _layout() -> void:
	_positions.clear()
	_next_row = 0.0
	var rows := {}
	for node in Database.tech_nodes.values():
		if node.parents.is_empty():
			_assign_row(node.id, rows)
	for id in rows:
		var node: TechNode = Database.tech_node(id)
		_positions[id] = ORIGIN + Vector2(node.column * COLUMN_WIDTH, rows[id] * ROW_HEIGHT)

func _assign_row(id: StringName, rows: Dictionary) -> float:
	if rows.has(id):
		return rows[id]
	var node: TechNode = Database.tech_node(id)
	if node.children.is_empty():
		rows[id] = _next_row
		_next_row += 1.0
		return rows[id]
	var total := 0.0
	for child_id in node.children:
		total += _assign_row(child_id, rows)
	rows[id] = total / node.children.size()
	return rows[id]

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.09, 0.12))
	var frontier := {}
	for id in Unlocks.available():
		frontier[id] = true
	var font := ThemeDB.fallback_font
	var half_height := NODE_SIZE.y * 0.5 * _zoom
	# elbow connectors leave each unlocked node toward any node that is drawn
	for node in Database.tech_nodes.values():
		if not Unlocks.is_unlocked(node.id):
			continue
		var start := _to_screen(node.id) + Vector2(NODE_SIZE.x * _zoom, half_height)
		for child_id in node.children:
			if not (Unlocks.is_unlocked(child_id) or frontier.has(child_id)):
				continue
			_draw_connector(start, _to_screen(child_id) + Vector2(0, half_height))
	# nodes
	for node in Database.tech_nodes.values():
		var unlocked := Unlocks.is_unlocked(node.id)
		if not unlocked and not frontier.has(node.id):
			continue   # past the frontier: hidden by the fog
		var rect := Rect2(_to_screen(node.id), NODE_SIZE * _zoom)
		_node_style.set_corner_radius_all(int(10 * _zoom))
		_node_style.set_border_width_all(1)
		if unlocked:
			_node_style.bg_color = _category_color(node.category)
			_node_style.border_color = Color(1, 1, 1, 0.25)
			draw_style_box(_node_style, rect)
			draw_string(font, rect.position + Vector2(8 * _zoom, half_height + 5 * _zoom), node.display_name, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12 * _zoom, int(13 * _zoom), Color(1, 1, 1))
		else:
			_node_style.bg_color = Color(0, 0, 0, 0.85)   # shadow of the next unlock
			_node_style.border_color = Color(1, 1, 1, 0.12)
			draw_style_box(_node_style, rect)

func _draw_connector(from: Vector2, to: Vector2) -> void:
	var color := Color(0.55, 0.55, 0.6)
	var width := maxf(1.5 * _zoom, 1.0)
	var mid_x := (from.x + to.x) * 0.5
	draw_line(from, Vector2(mid_x, from.y), color, width)
	draw_line(Vector2(mid_x, from.y), Vector2(mid_x, to.y), color, width)
	draw_line(Vector2(mid_x, to.y), to, color, width)

func _to_screen(id: StringName) -> Vector2:
	return _positions[id] * _zoom + _pan

func _category_color(category: StringName) -> Color:
	match category:
		&"machine": return Color(0.80, 0.45, 0.20)
		&"part": return Color(0.45, 0.55, 0.35)
		&"tool": return Color(0.30, 0.45, 0.70)
		&"material": return Color(0.55, 0.42, 0.28)
		&"buff": return Color(0.55, 0.40, 0.60)
	return Color(0.4, 0.4, 0.4)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_zoom_at(event.position, ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_zoom_at(event.position, -ZOOM_STEP)
		elif event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_pan += event.relative
		queue_redraw()

func _zoom_at(anchor: Vector2, step: float) -> void:
	var world := (anchor - _pan) / _zoom    # keep the point under the cursor fixed
	_zoom = clampf(_zoom + step, ZOOM_MIN, ZOOM_MAX)
	_pan = anchor - world * _zoom
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	closed.emit()
	queue_free()
