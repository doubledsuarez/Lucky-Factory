class_name SettingsPanel extends Control
## Reusable settings overlay with Sound, Video, and Key Binds tabs. Emits closed when dismissed.

signal closed

var _rebinding_action := ""
var _rebind_button: Button = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS   # usable while the game is paused
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var tabs := TabContainer.new()
	tabs.custom_minimum_size = Vector2(420, 320)
	tabs.add_child(_sound_tab())
	tabs.add_child(_video_tab())
	tabs.add_child(_keybinds_tab())
	column.add_child(tabs)
	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back)
	column.add_child(back)

# --- Sound ---

func _sound_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Sound"
	box.add_theme_constant_override("separation", 10)
	for bus in UserSettings.BUSES:
		box.add_child(_volume_row(bus))
	return box

func _volume_row(bus: String) -> Control:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.text = bus
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = UserSettings.volume_of(bus)
	slider.custom_minimum_size = Vector2(260, 0)
	slider.value_changed.connect(func(value): UserSettings.set_volume(bus, value))
	row.add_child(slider)
	return row

# --- Video ---

func _video_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Video"
	box.add_theme_constant_override("separation", 10)
	box.add_child(_label("Resolution"))
	var resolutions := OptionButton.new()
	var current := UserSettings.resolution()
	for index in range(UserSettings.RESOLUTIONS.size()):
		var size: Vector2i = UserSettings.RESOLUTIONS[index]
		resolutions.add_item("%d x %d" % [size.x, size.y])
		if size == current:
			resolutions.select(index)
	resolutions.item_selected.connect(func(index): UserSettings.set_resolution(UserSettings.RESOLUTIONS[index]))
	resolutions.disabled = UserSettings.is_fullscreen()
	box.add_child(resolutions)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = UserSettings.is_fullscreen()
	fullscreen.toggled.connect(func(on):
		UserSettings.set_fullscreen(on)
		resolutions.disabled = on)
	box.add_child(fullscreen)
	return box

# --- Key Binds ---

func _keybinds_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Key Binds"
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	for bind in UserSettings.BINDS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = bind.label
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		var button := Button.new()
		button.custom_minimum_size = Vector2(120, 0)
		button.text = OS.get_keycode_string(UserSettings.key_of(bind.action))
		button.pressed.connect(_begin_rebind.bind(bind.action, button))
		row.add_child(button)
		box.add_child(row)
	scroll.add_child(box)
	return scroll

func _begin_rebind(action: String, button: Button) -> void:
	_rebinding_action = action
	_rebind_button = button
	button.text = "Press a key..."

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if _rebinding_action != "":
		UserSettings.rebind(_rebinding_action, event.keycode)
		_rebind_button.text = OS.get_keycode_string(event.keycode)
		_rebinding_action = ""
		_rebind_button = null
		get_viewport().set_input_as_handled()
		return
	if event.keycode == KEY_ESCAPE:
		# close the settings overlay and swallow the key so it doesn't also unpause
		get_viewport().set_input_as_handled()
		_on_back()

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _on_back() -> void:
	closed.emit()
	queue_free()
