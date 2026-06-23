class_name SettingsPanel extends Control
## Reusable settings overlay with Sound, Video, and Key Binds tabs. Emits closed when dismissed.
## Layout lives in SettingsPanel.tscn; the rows inside each tab are filled from UserSettings here.

signal closed

@onready var _sound_box: VBoxContainer = $Center/Panel/Column/Tabs/Sound
@onready var _video_box: VBoxContainer = $Center/Panel/Column/Tabs/Video
@onready var _bind_list: VBoxContainer = get_node("Center/Panel/Column/Tabs/Key Binds/BindList")

var _rebinding_action := ""
var _rebind_button: Button = null

func _ready() -> void:
	for bus in UserSettings.BUSES:
		_sound_box.add_child(_volume_row(bus))
	_populate_video()
	for bind in UserSettings.BINDS:
		_bind_list.add_child(_bind_row(bind))

# --- Sound ---

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

func _populate_video() -> void:
	_video_box.add_child(_label("Resolution"))
	var resolutions := OptionButton.new()
	var current := UserSettings.resolution()
	for index in range(UserSettings.RESOLUTIONS.size()):
		var size: Vector2i = UserSettings.RESOLUTIONS[index]
		resolutions.add_item("%d x %d" % [size.x, size.y])
		if size == current:
			resolutions.select(index)
	resolutions.item_selected.connect(func(index): UserSettings.set_resolution(UserSettings.RESOLUTIONS[index]))
	resolutions.disabled = UserSettings.is_fullscreen()
	_video_box.add_child(resolutions)
	var fullscreen := CheckButton.new()
	fullscreen.text = "Fullscreen"
	fullscreen.button_pressed = UserSettings.is_fullscreen()
	fullscreen.toggled.connect(func(on):
		UserSettings.set_fullscreen(on)
		resolutions.disabled = on)
	_video_box.add_child(fullscreen)

# --- Key Binds ---

func _bind_row(bind) -> Control:
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
	return row

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
