extends Node
## Owns scene flow between the menu and the factory, plus the active save slot.

const MAIN_MENU := "res://ui/MainMenu.tscn"
const FACTORY := "res://factory/Factory.tscn"

var current_slot: int = -1
var _pending_load: Dictionary = {}   # factory snapshot to restore on the next factory load

func new_game(slot: int) -> void:
	current_slot = slot
	_pending_load = {}
	SaveManager.delete_slot(slot)   # start the slot fresh; first autosave writes wave 1
	get_tree().change_scene_to_file(FACTORY)

func load_game(slot: int) -> void:
	current_slot = slot
	_pending_load = SaveManager.load_slot(slot)
	get_tree().change_scene_to_file(FACTORY)

# the factory calls this in _ready; empty dict means start a fresh floor
func take_pending_load() -> Dictionary:
	var data := _pending_load
	_pending_load = {}
	return data

func to_menu() -> void:
	current_slot = -1
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU)

# manual save and the wave-start autosave both route through here
func save_snapshot(snapshot: Dictionary) -> bool:
	if current_slot < 0:
		return false
	return SaveManager.save_slot(current_slot, snapshot)
