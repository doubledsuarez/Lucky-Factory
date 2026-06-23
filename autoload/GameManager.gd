extends Node
## Owns scene flow between the menu and the factory, plus the active save slot.

const MAIN_MENU := "res://ui/MainMenu.tscn"
const FACTORY := "res://factory/Factory.tscn"

signal battle_resolved(won: bool, card_count: int)

var current_slot: int = -1
var current_save_name: String = ""
var _pending_load: Dictionary = {}   # factory snapshot to restore on the next factory load

# the battle phase calls this with its result; the factory reacts to battle_resolved
func on_battle_done(result: BattleResult) -> void:
	if not result.won:
		battle_resolved.emit(false, 0)
		return
	var underdog := result.sent_power() < result.enemy_power()          # won against the odds
	var dominant := result.survivor_power() > result.sent_power() * 0.5  # kept over half our power
	battle_resolved.emit(true, 3 if (underdog or dominant) else 2)

func new_game(slot: int, save_name: String) -> void:
	current_slot = slot
	current_save_name = save_name
	_pending_load = {}
	SaveManager.delete_slot(slot)   # start the slot fresh; the factory autosaves wave 1 on load
	get_tree().change_scene_to_file(FACTORY)

func load_game(slot: int) -> void:
	current_slot = slot
	_pending_load = SaveManager.load_slot(slot)
	get_tree().change_scene_to_file(FACTORY)

# empty dictionary means start a fresh floor
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
