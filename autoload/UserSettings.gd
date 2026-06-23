extends Node
## Persists audio, video, and keybind settings to user://settings.cfg and applies them on boot.

const CONFIG_PATH := "user://settings.cfg"
const BUSES := ["Master", "Music", "SFX"]
const RESOLUTIONS := [Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440)]

# game actions and their default keys, in display order
const BINDS := [
	{ "action": "build_belt", "label": "Build: Belt", "key": KEY_B },
	{ "action": "build_forge", "label": "Build: Forge", "key": KEY_F },
	{ "action": "build_crafter", "label": "Build: Crafter", "key": KEY_C },
	{ "action": "build_assembler", "label": "Build: Assembler", "key": KEY_A },
	{ "action": "build_bank", "label": "Build: Bank", "key": KEY_K },
	{ "action": "build_splitter", "label": "Build: Splitter", "key": KEY_S },
	{ "action": "build_merger", "label": "Build: Merger", "key": KEY_M },
	{ "action": "rotate", "label": "Rotate piece", "key": KEY_R },
	{ "action": "tech_tree", "label": "Tech Tree", "key": KEY_T },
	{ "action": "speed_slow", "label": "Speed 0.5x", "key": KEY_1 },
	{ "action": "speed_normal", "label": "Speed 1x", "key": KEY_2 },
	{ "action": "speed_fast", "label": "Speed 2x", "key": KEY_3 },
	{ "action": "pause", "label": "Pause", "key": KEY_ESCAPE },
]

var _config := ConfigFile.new()

func _ready() -> void:
	_config.load(CONFIG_PATH)
	_setup_actions()
	_apply_audio()
	_apply_display()

# --- keybinds ---

func _setup_actions() -> void:
	for bind in BINDS:
		var action: String = bind.action
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var keycode := int(_config.get_value("keybinds", action, bind.key))
		_assign_key(action, keycode)

func _assign_key(action: String, keycode: int) -> void:
	InputMap.action_erase_events(action)
	var event := InputEventKey.new()
	event.keycode = keycode
	InputMap.action_add_event(action, event)

func key_of(action: String) -> int:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.keycode
	return KEY_NONE

func rebind(action: String, keycode: int) -> void:
	_assign_key(action, keycode)
	_config.set_value("keybinds", action, keycode)
	_save()

# --- audio ---

func volume_of(bus: String) -> float:
	return _config.get_value("audio", bus, 1.0)

func set_volume(bus: String, value: float) -> void:
	_config.set_value("audio", bus, value)
	_apply_bus(bus, value)
	_save()

func _apply_audio() -> void:
	for bus in BUSES:
		_apply_bus(bus, volume_of(bus))

func _apply_bus(bus: String, value: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.0001)))

# --- video ---

func is_fullscreen() -> bool:
	return _config.get_value("video", "fullscreen", false)

func set_fullscreen(on: bool) -> void:
	_config.set_value("video", "fullscreen", on)
	_apply_display()
	_save()

func resolution() -> Vector2i:
	var stored = _config.get_value("video", "resolution", [1280, 720])
	return Vector2i(int(stored[0]), int(stored[1]))

func set_resolution(size: Vector2i) -> void:
	_config.set_value("video", "resolution", [size.x, size.y])
	_apply_display()
	_save()

func _apply_display() -> void:
	if is_fullscreen():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var size := resolution()
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position((screen - size) / 2)

func _save() -> void:
	_config.save(CONFIG_PATH)
