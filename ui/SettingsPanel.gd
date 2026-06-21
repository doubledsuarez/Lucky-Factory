class_name SettingsPanel extends Control
## Reusable settings overlay: master volume + fullscreen. Emits closed when dismissed.

signal closed

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
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(320, 0)
	panel.add_child(column)
	var title := Label.new()
	title.text = "Settings"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	column.add_child(_label("Master volume"))
	var volume := HSlider.new()
	volume.min_value = 0.0
	volume.max_value = 1.0
	volume.step = 0.01
	volume.value = _current_volume()
	volume.value_changed.connect(_on_volume_changed)
	column.add_child(volume)

	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen.toggled.connect(_on_fullscreen_toggled)
	column.add_child(fullscreen)

	var back := Button.new()
	back.text = "Back"
	back.pressed.connect(_on_back)
	column.add_child(back)

func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label

func _current_volume() -> float:
	return db_to_linear(AudioServer.get_bus_volume_db(0))

func _on_volume_changed(value: float) -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(value, 0.0001)))

func _on_fullscreen_toggled(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_MAXIMIZED)

func _on_back() -> void:
	closed.emit()
	queue_free()
