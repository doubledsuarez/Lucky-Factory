extends Node
## Reads and writes the three save slots as JSON under user://.

const SLOT_COUNT := 3

func slot_path(slot: int) -> String:
	return "user://slot_%d.save" % slot

func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

func any_slot_exists() -> bool:
	for slot in range(SLOT_COUNT):
		if slot_exists(slot):
			return true
	return false

func save_slot(slot: int, snapshot: Dictionary) -> bool:
	snapshot["saved_at"] = Time.get_datetime_string_from_system(false, true)
	var file := FileAccess.open(slot_path(slot), FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(snapshot))
	file.close()
	return true

func load_slot(slot: int) -> Dictionary:
	if not slot_exists(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func delete_slot(slot: int) -> void:
	if slot_exists(slot):
		DirAccess.remove_absolute(slot_path(slot))

# short one-line description for the slot button on the menu
func slot_summary(slot: int) -> String:
	var data := load_slot(slot)
	if data.is_empty():
		return "Empty"
	return "Wave %d   %s" % [int(data.get("wave", 1)), data.get("saved_at", "")]
