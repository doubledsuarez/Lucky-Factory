class_name PauseMenu extends Control
## In-factory pause overlay. Its buttons fire signals the factory hooks into.
## Layout lives in PauseMenu.tscn; the buttons are wired to the handlers there.

signal resume_requested
signal save_requested
signal settings_requested
signal tech_tree_requested
signal exit_requested

func _on_resume_pressed() -> void: resume_requested.emit()
func _on_save_pressed() -> void: save_requested.emit()
func _on_tech_tree_pressed() -> void: tech_tree_requested.emit()
func _on_settings_pressed() -> void: settings_requested.emit()
func _on_exit_pressed() -> void: exit_requested.emit()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		resume_requested.emit()
		get_viewport().set_input_as_handled()
