extends Control
## Placeholder game UI on its own layer (ignores the camera): a top status bar and a bottom build bar.
## Graphics are stand-in styled panels/buttons until real art lands.

@onready var factory: Node = owner

const BAR_COLOR := Color(0.10, 0.10, 0.12, 0.85)

const SPEEDS := [0.5, 1.0, 2.0]

var scrap_label: Label
var ingot_label: Label
var timer_label: Label
var manifest_button: Button
var shuttle_panel: PanelContainer
var shuttle_list: VBoxContainer
var launch_button: Button
var tool_buttons := {}   # tool -> Button
var tool_costs := {}     # tool -> int
var speed_buttons := {}  # speed -> Button
var last_robot_state := ""
var machine_panel: Control = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top_bar()
	_build_build_bar()
	_build_launch_button()
	_build_controls_hint()
	_build_shuttle_panel()

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
	timer_label = _make_label("30:00")
	timer_label.add_theme_font_size_override("font_size", 18)
	row.add_child(timer_label)
	row.add_child(_make_spacer())
	manifest_button = Button.new()
	manifest_button.text = "Robots: 0"
	manifest_button.pressed.connect(toggle_shuttle_panel)
	row.add_child(manifest_button)

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
	launch_button.custom_minimum_size = Vector2(128, 128)
	launch_button.offset_left = -140
	launch_button.offset_right = -12
	launch_button.offset_top = 8
	launch_button.offset_bottom = 136
	launch_button.text = "PRIME"
	launch_button.add_theme_font_size_override("font_size", 24)
	launch_button.add_theme_stylebox_override("normal", _icon_style(Color(0.72, 0.16, 0.16)))
	launch_button.add_theme_stylebox_override("hover", _icon_style(Color(0.82, 0.22, 0.22)))
	launch_button.add_theme_stylebox_override("pressed", _icon_style(Color(0.90, 0.30, 0.30)))
	launch_button.add_theme_stylebox_override("disabled", _icon_style(Color(0.40, 0.13, 0.13)))
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

# --- shuttle manifest (toggled from the top bar) ---

func _build_shuttle_panel() -> void:
	shuttle_panel = PanelContainer.new()
	shuttle_panel.anchor_left = 1.0
	shuttle_panel.anchor_right = 1.0
	shuttle_panel.anchor_top = 0.0
	shuttle_panel.anchor_bottom = 1.0
	shuttle_panel.offset_left = -250
	shuttle_panel.offset_right = -12
	shuttle_panel.offset_top = 148   # below the launch button
	shuttle_panel.offset_bottom = -92
	shuttle_panel.add_theme_stylebox_override("panel", _panel_style(BAR_COLOR))
	shuttle_panel.visible = false     # hidden until the player opens it, so it doesn't cover the floor
	add_child(shuttle_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	shuttle_panel.add_child(column)
	var title := _make_label("Shuttle manifest")
	title.add_theme_font_size_override("font_size", 14)
	column.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	shuttle_list = VBoxContainer.new()
	shuttle_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shuttle_list.add_theme_constant_override("separation", 4)
	scroll.add_child(shuttle_list)

func toggle_shuttle_panel() -> void:
	shuttle_panel.visible = not shuttle_panel.visible
	if shuttle_panel.visible:
		_rebuild_shuttle_list(factory.robot_groups())

func _rebuild_shuttle_list(groups: Array) -> void:
	for child in shuttle_list.get_children():
		child.free()
	if groups.is_empty():
		shuttle_list.add_child(_make_label("Shuttle empty"))
		return
	for group in groups:
		shuttle_list.add_child(_make_robot_card(group))

func _make_robot_card(group: Dictionary) -> Control:
	var loadout = group.loadout
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", _icon_style(Color(0.18, 0.18, 0.24)))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	card.add_child(box)
	var header := _make_label("x%d" % group.count)
	header.add_theme_font_size_override("font_size", 13)
	box.add_child(header)
	box.add_child(_make_wrapped_label(_loadout_parts_text(loadout), Color(1, 1, 1)))
	box.add_child(_make_wrapped_label(_loadout_stats_text(loadout), Color(0.82, 0.88, 0.95)))
	return card

func _make_wrapped_label(text: String, color: Color) -> Label:
	var label := _make_label(text)
	label.add_theme_font_size_override("font_size", 10)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.modulate = color
	return label

func _loadout_parts_text(loadout) -> String:
	return "%s · %s · %s · %s" % [
		_strip_scrap(loadout.head.display_name), _strip_scrap(loadout.torso.display_name),
		_strip_scrap(loadout.legs.display_name), _strip_scrap(loadout.arms.display_name)]

func _loadout_stats_text(loadout) -> String:
	return "ARM %d   DMG %d   RNG %.0f   ATK %.1f   SPD %.2f   TRN %.2f" % [
		loadout.total_armor(), loadout.damage(), loadout.attack_range(),
		loadout.attack_speed(), loadout.move_speed(), loadout.turn_rate()]

func _strip_scrap(part_name: String) -> String:
	return part_name.trim_prefix("Scrap ")

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
	button.custom_minimum_size = Vector2(64, 52)
	button.text = entry.name
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", _icon_style(entry.color))
	button.add_theme_stylebox_override("hover", _icon_style(entry.color.lightened(0.12)))
	button.add_theme_stylebox_override("pressed", _icon_style(entry.color.lightened(0.2)))
	button.pressed.connect(_on_build_pressed.bind(entry.tool))
	_add_cost_badge(button, entry.cost)
	box.add_child(button)
	var hotkey := _make_label("[%s]" % entry.hotkey)
	hotkey.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hotkey.add_theme_font_size_override("font_size", 10)
	box.add_child(hotkey)
	tool_buttons[entry.tool] = button
	tool_costs[entry.tool] = entry.cost
	return box

# ingot icon + cost number tucked into the bottom-left corner of a build button
func _add_cost_badge(button: Button, cost: int) -> void:
	var icon := _make_item_chip(&"ingot")
	icon.custom_minimum_size = Vector2.ZERO
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.anchor_top = 1.0
	icon.anchor_bottom = 1.0
	icon.offset_left = 3
	icon.offset_right = 15
	icon.offset_top = -15
	icon.offset_bottom = -3
	button.add_child(icon)
	var cost_label := Label.new()
	cost_label.text = str(cost)
	cost_label.add_theme_font_size_override("font_size", 10)
	cost_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_label.anchor_top = 1.0
	cost_label.anchor_bottom = 1.0
	cost_label.offset_left = 17
	cost_label.offset_right = 56
	cost_label.offset_top = -16
	cost_label.offset_bottom = -2
	button.add_child(cost_label)

# --- dynamic bits ---

func _refresh_robots() -> void:
	var groups: Array = factory.robot_groups()
	var state := ""
	var total := 0
	for group in groups:
		state += "%s:%d," % [group.signature, group.count]
		total += group.count
	if state == last_robot_state:
		return
	last_robot_state = state
	manifest_button.text = "Robots: %d" % total
	if shuttle_panel.visible:
		_rebuild_shuttle_list(groups)

func _refresh_launch() -> void:
	var has_robots: bool = not factory.robot_groups().is_empty()
	if factory.launch_armed and not has_robots:
		factory.disarm_launch()       # the shuttle emptied out, so drop back to unprimed
	launch_button.disabled = not has_robots
	launch_button.text = "LAUNCH" if factory.launch_armed else "PRIME"
	launch_button.modulate = Color(1.2, 1.0, 1.0) if factory.launch_armed else Color(1, 1, 1)

func _refresh_speed() -> void:
	for speed in speed_buttons:
		speed_buttons[speed].modulate = Color(1, 1, 1) if is_equal_approx(speed, Sim.speed) else Color(0.6, 0.6, 0.6)

func _refresh_buildables() -> void:
	for tool in tool_buttons:
		var affordable: bool = int(factory.build_ingots) >= int(tool_costs[tool])
		var tint := Color(1, 1, 1) if affordable else Color(0.38, 0.38, 0.38)
		if tool == factory.selected_tool:
			tint *= 1.3   # overbright glow so the active tool still stands out
		tool_buttons[tool].modulate = tint

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

# --- machine config panel (opened by clicking a placed machine) ---

func open_machine_panel(machine) -> void:
	_close_machine_panel()
	var recipes: Array = machine.definition.recipes
	if recipes.is_empty():
		return  # nothing to configure yet; slot view for other machines comes later
	var holder := CenterContainer.new()
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	machine_panel = holder
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style(BAR_COLOR))
	holder.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	var header := HBoxContainer.new()
	var title := _make_label("Choose a part to craft")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "X"
	close.pressed.connect(_close_machine_panel)
	header.add_child(close)
	column.add_child(header)
	var grid := GridContainer.new()
	grid.columns = 3   # 3 variants across, one slot per row
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	column.add_child(grid)
	for recipe in recipes:
		grid.add_child(_make_recipe_button(machine, recipe))

func _make_recipe_button(machine, recipe) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(124, 40)
	button.add_theme_font_size_override("font_size", 11)
	var part: ItemDef = Database.item(recipe.output_id)
	button.text = "%s\n%d ingots" % [part.display_name, int(recipe.inputs.get(&"ingot", 0))]
	if machine.recipe == recipe:
		button.modulate = Color(0.6, 1.0, 0.6)  # the recipe this machine is already set to
	button.pressed.connect(_on_recipe_chosen.bind(machine, recipe))
	return button

func _on_recipe_chosen(machine, recipe) -> void:
	factory.assign_recipe(machine, recipe)
	_close_machine_panel()

func _close_machine_panel() -> void:
	if machine_panel != null:
		machine_panel.queue_free()
		machine_panel = null

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
