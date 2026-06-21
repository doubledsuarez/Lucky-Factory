extends Control
## Title screen: New Game, Load Game (only when saves exist), Settings, Exit.

var _overlay: Control = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.09, 0.12)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	column.custom_minimum_size = Vector2(260, 0)
	center.add_child(column)
	var title := Label.new()
	title.text = "Lucky Factory"
	title.add_theme_font_size_override("font_size", 40)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(title)
	column.add_child(_button("New Game", _on_new_game))
	if SaveManager.any_slot_exists():
		column.add_child(_button("Load Game", _on_load_game))
	column.add_child(_button("Settings", _on_settings))
	column.add_child(_button("Exit to Desktop", _on_exit))

func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(handler)
	return button

func _on_new_game() -> void:
	_open_slots("new")

func _on_load_game() -> void:
	_open_slots("load")

func _on_settings() -> void:
	_close_overlay()
	var settings := SettingsPanel.new()
	_overlay = settings
	add_child(settings)
	settings.closed.connect(func(): _overlay = null)

func _on_exit() -> void:
	get_tree().quit()

func _open_slots(mode: String) -> void:
	_close_overlay()
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.custom_minimum_size = Vector2(340, 0)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "Choose a slot to load" if mode == "load" else "Choose a slot"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	for slot in range(SaveManager.SLOT_COUNT):
		var button := Button.new()
		button.text = "Slot %d   —   %s" % [slot + 1, SaveManager.slot_summary(slot)]
		button.custom_minimum_size = Vector2(0, 36)
		if mode == "load" and not SaveManager.slot_exists(slot):
			button.disabled = true
		button.pressed.connect(_on_slot_chosen.bind(mode, slot))
		column.add_child(button)
	column.add_child(_button("Back", _close_overlay))
	_overlay = overlay
	add_child(overlay)

func _on_slot_chosen(mode: String, slot: int) -> void:
	if mode == "load":
		GameManager.load_game(slot)
	else:
		GameManager.new_game(slot)

func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
