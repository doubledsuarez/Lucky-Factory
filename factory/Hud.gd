extends Control
## Placeholder game UI on its own layer (ignores the camera): a top status bar and a bottom build bar.
## Graphics are stand-in styled panels/buttons until real art lands.

@onready var factory: Node = owner

const BAR_COLOR := Color(0.10, 0.10, 0.12, 0.85)

const SPEEDS := [0.5, 1.0, 2.0]

var scrap_label: Label
var ingot_label: Label
var timer_label: Label
var robot_row: HBoxContainer
var launch_button: Button
var tool_buttons := {}   # tool -> Button
var tool_costs := {}     # tool -> int
var speed_buttons := {}  # speed -> Button
var last_robot_state := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_build_bar()
	_build_launch_button()
	_build_controls_hint()

func _process(_delta: float) -> void:
	scrap_label.text = str(factory.scrap_total())
	ingot_label.text = str(factory.build_ingots)
	timer_label.text = factory.time_text()
	_refresh_robots()
	_refresh_launch()
	_refresh_speed()
	_refresh_buildables()

# --- top status bar ---

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_stylebox_override("panel", _panel_style(BAR_COLOR))
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.custom_minimum_size = Vector2(0, 32)
	bar.add_child(row)
	row.add_child(_build_speed_control())
	row.add_child(_make_item_chip(&"scrap"))
	scrap_label = _make_label("0")
	row.add_child(scrap_label)
	row.add_child(_make_item_chip(&"ingot"))
	ingot_label = _make_label("0")
	row.add_child(ingot_label)
	row.add_child(_make_spacer())
	timer_label = _make_label("4:00")
	timer_label.add_theme_font_size_override("font_size", 18)
	row.add_child(timer_label)
	row.add_child(_make_spacer())
	robot_row = HBoxContainer.new()
	robot_row.add_theme_constant_override("separation", 6)
	row.add_child(robot_row)

# --- bottom build bar ---

func _build_build_bar() -> void:
	# full-width strip at the bottom that centers the bar; empty areas pass clicks to the world
	var holder := Control.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	holder.offset_top = -80
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(center)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _panel_style(BAR_COLOR))
	center.add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	for entry in factory.buildables():
		row.add_child(_make_build_entry(entry))

# --- launch button (big square, top right) ---

func _build_launch_button() -> void:
	launch_button = Button.new()
	launch_button.anchor_left = 1.0
	launch_button.anchor_right = 1.0
	launch_button.custom_minimum_size = Vector2(96, 96)
	launch_button.offset_left = -108
	launch_button.offset_right = -12
	launch_button.offset_top = 44
	launch_button.offset_bottom = 140
	launch_button.text = "PRIME"
	launch_button.add_theme_font_size_override("font_size", 18)
	launch_button.add_theme_stylebox_override("normal", _icon_style(Color(0.45, 0.18, 0.18)))
	launch_button.add_theme_stylebox_override("hover", _icon_style(Color(0.55, 0.22, 0.22)))
	launch_button.add_theme_stylebox_override("pressed", _icon_style(Color(0.65, 0.28, 0.28)))
	launch_button.pressed.connect(_on_launch_pressed)
	add_child(launch_button)

# --- controls hint (bottom right) ---

func _build_controls_hint() -> void:
	var bar := PanelContainer.new()
	bar.anchor_left = 1.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = -150
	bar.offset_top = -64
	bar.offset_right = -12
	bar.offset_bottom = -12
	bar.add_theme_stylebox_override("panel", _panel_style(BAR_COLOR))
	add_child(bar)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	bar.add_child(column)
	column.add_child(_make_hint_label("[R]", "Rotate"))
	column.add_child(_make_hint_label("[MMB]", "Pan / Pick"))

func _make_hint_label(keys: String, action: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var key := _make_label(keys)
	key.add_theme_font_size_override("font_size", 11)
	key.custom_minimum_size = Vector2(44, 0)
	row.add_child(key)
	var label := _make_label(action)
	label.add_theme_font_size_override("font_size", 11)
	row.add_child(label)
	return row

func _make_build_entry(entry: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var button := Button.new()
	button.custom_minimum_size = Vector2(60, 44)
	button.text = entry.name
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _icon_style(entry.color))
	button.add_theme_stylebox_override("hover", _icon_style(entry.color.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _icon_style(entry.color.lightened(0.2)))
	button.pressed.connect(_on_build_pressed.bind(entry.tool))
	box.add_child(button)
	var hotkey := _make_label("[%s]" % entry.hotkey)
	hotkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotkey.add_theme_font_size_override("font_size", 10)
	box.add_child(hotkey)
	tool_buttons[entry.tool] = button
	tool_costs[entry.tool] = entry.cost
	return box

# --- dynamic bits ---

func _refresh_robots() -> void:
	var groups: Array = factory.robot_groups()
	var state := ""
	for group in groups:
		state += "%s:%d," % [group.signature, group.count]
	if state == last_robot_state:
		return
	last_robot_state = state
	for child in robot_row.get_children():
		child.free()
	for group in groups:
		robot_row.add_child(_make_item_chip(&"robot"))
		robot_row.add_child(_make_label("x%d" % group.count))

func _refresh_launch() -> void:
	var has_robots: bool = not factory.robot_groups().is_empty()
	launch_button.disabled = not has_robots and not factory.launch_armed
	if factory.launch_armed:
		launch_button.text = "LAUNCH"
		launch_button.modulate = Color(1.3, 0.8, 0.8)
	elif not has_robots:
		launch_button.text = "PRIME"
		launch_button.modulate = Color(0.5, 0.5, 0.5)
	else:
		launch_button.text = "PRIME"
		launch_button.modulate = Color(1, 1, 1)

func _refresh_speed() -> void:
	for speed in speed_buttons:
		speed_buttons[speed].modulate = Color(1, 1, 1) if is_equal_approx(speed, Sim.speed) else Color(0.6, 0.6, 0.6)

func _refresh_buildables() -> void:
	for tool in tool_buttons:
		var affordable: bool = int(factory.build_ingots) >= int(tool_costs[tool])
		if tool == factory.selected_tool:
			tool_buttons[tool].modulate = Color(1, 1, 1)
		elif affordable:
			tool_buttons[tool].modulate = Color(0.7, 0.7, 0.7)
		else:
			tool_buttons[tool].modulate = Color(0.4, 0.4, 0.4)

func _on_launch_pressed() -> void:
	if factory.launch_armed:
		factory.confirm_launch()
	else:
		factory.arm_launch()

func _build_speed_control() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	for speed in SPEEDS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(34, 24)
		button.text = "%sx" % str(speed)
		button.add_theme_font_size_override("font_size", 11)
		button.pressed.connect(_on_speed_pressed.bind(speed))
		row.add_child(button)
		speed_buttons[speed] = button
	return row

func _on_speed_pressed(speed: float) -> void:
	Sim.speed = speed

func _on_build_pressed(tool: int) -> void:
	factory.select_build_tool(tool)

# --- placeholder graphics helpers ---

func _make_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _make_item_chip(item_id: StringName) -> Control:
	var definition: ItemDef = Database.item(item_id)
	var chip := Control.new()
	chip.custom_minimum_size = Vector2(18, 18)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.draw.connect(_draw_item_icon.bind(chip, definition))
	chip.resized.connect(chip.queue_redraw)
	return chip

func _draw_item_icon(canvas: Control, definition: ItemDef) -> void:
	var center := canvas.size * 0.5
	var half := minf(canvas.size.x, canvas.size.y) * 0.45
	var color := definition.color
	match definition.shape:
		ItemDef.Shape.CIRCLE:
			canvas.draw_circle(center, half, color)
		ItemDef.Shape.TRAPEZOID:
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(-half * 0.55, -half), center + Vector2(half * 0.55, -half),
				center + Vector2(half, half), center + Vector2(-half, half)]), color)
		ItemDef.Shape.TRIANGLE:
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -half), center + Vector2(half, half), center + Vector2(-half, half)]), color)
		ItemDef.Shape.DIAMOND:
			canvas.draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -half), center + Vector2(half, 0), center + Vector2(0, half), center + Vector2(-half, 0)]), color)
		ItemDef.Shape.HEXAGON:
			var points := PackedVector2Array()
			for index in range(6):
				var angle := -PI * 0.5 + index * (PI / 3.0)
				points.append(center + Vector2(cos(angle), sin(angle)) * half)
			canvas.draw_colored_polygon(points, color)
		_:
			canvas.draw_rect(Rect2(center - Vector2(half, half), Vector2(half, half) * 2.0), color)

func _make_spacer() -> Control:
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return spacer

func _panel_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

func _icon_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	return style
