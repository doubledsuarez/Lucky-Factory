extends Control
## Title screen: New Game, Load Game (only when saves exist), Settings, Exit.
## Layout lives in MainMenu.tscn. The slot picker, name entry, and the live factory
## backdrop are built here at runtime because they depend on the current saves.

@onready var _preview_mount: Control = $PreviewMount
@onready var _load_button: Button = $Center/Backdrop/Menu/LoadGameButton

var _overlay: Control = null
var _manage_mode := false
var _preview_camera: Camera2D = null
var _preview_time := 0.0
var _pan_left := 0.0
var _pan_right := 0.0
var _preview_y := 0.0
var _preview_zoom := 0.6

func _ready() -> void:
	_load_button.visible = SaveManager.any_slot_exists()
	_build_preview_background()

func _button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 40)
	button.pressed.connect(handler)
	return button

func _on_new_game() -> void:
	_manage_mode = false
	_open_slots("new")

func _on_load_game() -> void:
	_open_slots("load")

func _on_settings() -> void:
	_close_overlay()
	var settings := preload("res://ui/SettingsPanel.tscn").instantiate() as SettingsPanel
	_overlay = settings
	add_child(settings)
	settings.closed.connect(func(): _overlay = null)

func _on_exit() -> void:
	get_tree().quit()

# render the most recent save as a frozen, wobbling backdrop (purely cosmetic; never saved)
func _build_preview_background() -> void:
	var snapshot := SaveManager.most_recent_snapshot()
	if snapshot.is_empty():
		return   # no save yet, keep the solid background
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_mount.add_child(container)
	var viewport := SubViewport.new()
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_2d = Viewport.MSAA_4X   # smooth the rotated edges (preview only)
	container.add_child(viewport)
	var factory := preload("res://factory/Factory.tscn").instantiate()
	factory.preview_mode = true
	factory.preview_snapshot = snapshot
	factory.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR   # soften the scaled belt sprites
	viewport.add_child(factory)
	_preview_camera = factory.camera
	# frame the content's height, then set the left/right ends of the slow horizontal sweep
	var bounds: Rect2 = factory.preview_bounds
	var view := Vector2(1280, 720)
	# zoom in enough to show ~70% of the width at once (so there's something to pan across),
	# but never so far that the content's height stops fitting
	var zoom_for_height := view.y / (bounds.size.y + 80.0)
	var zoom_for_pan := view.x / maxf(bounds.size.x * 0.7, 1.0)
	_preview_zoom = clampf(minf(zoom_for_height, zoom_for_pan), 0.5, 1.1)
	_preview_y = bounds.get_center().y
	var visible_width := view.x / _preview_zoom
	if bounds.size.x <= visible_width:
		_pan_left = bounds.get_center().x
		_pan_right = _pan_left
	else:
		_pan_left = bounds.position.x + visible_width * 0.5
		_pan_right = bounds.end.x - visible_width * 0.5

func _process(delta: float) -> void:
	if _preview_camera == null:
		return
	_preview_time += delta
	var sweep := (sin(_preview_time * 0.2) + 1.0) * 0.5   # 0..1, slow left to right to left
	_preview_camera.zoom = Vector2(_preview_zoom, _preview_zoom)
	_preview_camera.position = Vector2(lerpf(_pan_left, _pan_right, sweep), _preview_y)

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
	heading.text = "Load a save" if mode == "load" else "New game — choose a slot"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	for slot in range(SaveManager.SLOT_COUNT):
		var info: Dictionary = SaveManager.slot_info(slot)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var button := Button.new()
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size = Vector2(300, 48)
		button.add_theme_font_size_override("font_size", 13)
		if info.exists:
			button.text = "%s\nWave %d   •   Played %s" % [info.name, info.wave, SaveManager.format_played(info.played)]
		else:
			button.text = "Slot %d\nEmpty" % (slot + 1)
		if mode == "load":
			button.disabled = not info.exists
		else:
			button.disabled = info.exists   # occupied slots can't be overwritten; delete to reuse
			if info.exists:
				button.tooltip_text = "Delete this save (Manage Saves) to reuse the slot"
		button.pressed.connect(_on_slot_chosen.bind(mode, slot))
		row.add_child(button)
		if mode == "new" and _manage_mode and info.exists:
			row.add_child(_make_trash_button(slot))
		column.add_child(row)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	footer.add_child(_button("Back", _close_overlay))
	if mode == "new":
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		footer.add_child(spacer)
		footer.add_child(_button("Done" if _manage_mode else "Manage Saves", _toggle_manage))
	column.add_child(footer)
	_overlay = overlay
	add_child(overlay)

func _toggle_manage() -> void:
	_manage_mode = not _manage_mode
	_open_slots("new")

func _make_trash_button(slot: int) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(40, 48)
	button.tooltip_text = "Delete save"
	button.draw.connect(_draw_trash.bind(button))
	button.pressed.connect(_confirm_delete.bind(slot))
	return button

func _draw_trash(button: Button) -> void:
	var size := button.size
	var color := Color(0.92, 0.45, 0.45)
	button.draw_line(Vector2(size.x * 0.28, size.y * 0.34), Vector2(size.x * 0.72, size.y * 0.34), color, 2.0)
	button.draw_line(Vector2(size.x * 0.42, size.y * 0.28), Vector2(size.x * 0.58, size.y * 0.28), color, 2.0)
	button.draw_line(Vector2(size.x * 0.33, size.y * 0.38), Vector2(size.x * 0.37, size.y * 0.72), color, 2.0)
	button.draw_line(Vector2(size.x * 0.67, size.y * 0.38), Vector2(size.x * 0.63, size.y * 0.72), color, 2.0)
	button.draw_line(Vector2(size.x * 0.37, size.y * 0.72), Vector2(size.x * 0.63, size.y * 0.72), color, 2.0)
	button.draw_line(Vector2(size.x * 0.46, size.y * 0.42), Vector2(size.x * 0.46, size.y * 0.68), color, 1.0)
	button.draw_line(Vector2(size.x * 0.54, size.y * 0.42), Vector2(size.x * 0.54, size.y * 0.68), color, 1.0)

func _confirm_delete(slot: int) -> void:
	var dialog := ConfirmationDialog.new()
	dialog.dialog_text = "Are you sure you want to delete this save?"
	dialog.ok_button_text = "Delete"
	add_child(dialog)
	dialog.confirmed.connect(func():
		SaveManager.delete_slot(slot)
		dialog.queue_free()
		_open_slots("new"))
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered()

func _on_slot_chosen(mode: String, slot: int) -> void:
	if mode == "load":
		GameManager.load_game(slot)
	else:
		_open_name_entry(slot)

func _open_name_entry(slot: int) -> void:
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
	column.custom_minimum_size = Vector2(320, 0)
	panel.add_child(column)
	var heading := Label.new()
	heading.text = "Name your save"
	heading.add_theme_font_size_override("font_size", 20)
	column.add_child(heading)
	if SaveManager.slot_exists(slot):
		var warn := Label.new()
		warn.text = "This overwrites Slot %d." % (slot + 1)
		warn.modulate = Color(1.0, 0.7, 0.5)
		column.add_child(warn)
	var line := LineEdit.new()
	line.placeholder_text = "Save name"
	line.text = "Save %d" % (slot + 1)
	line.max_length = 24
	line.text_submitted.connect(func(_text): _start_new(slot, line.text))
	column.add_child(line)
	column.add_child(_button("Start", func(): _start_new(slot, line.text)))
	column.add_child(_button("Back", func(): _open_slots("new")))
	_overlay = overlay
	add_child(overlay)
	line.call_deferred("grab_focus")

func _start_new(slot: int, save_name: String) -> void:
	var trimmed := save_name.strip_edges()
	if trimmed.is_empty():
		trimmed = "Save %d" % (slot + 1)
	GameManager.new_game(slot, trimmed)

func _close_overlay() -> void:
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null
