extends Node
## Tracks which tech nodes are unlocked this run. Seeded on new game, saved/restored with the run.

var unlocked: Dictionary = {}   # node id -> true

func seed_new_game() -> void:
	unlocked.clear()
	for node in Database.tech_nodes.values():
		if node.starts_unlocked:
			unlocked[node.id] = true

# dev helper: a save named "playtest" starts with everything unlocked
func unlock_all() -> void:
	unlocked.clear()
	for node in Database.tech_nodes.values():
		unlocked[node.id] = true

func is_unlocked(id: StringName) -> bool:
	return unlocked.has(id)

func unlock(id: StringName) -> void:
	unlocked[id] = true

# locked nodes whose parents are all unlocked -- the picker's pool and the tree's fog frontier
func available() -> Array:
	var result := []
	for node in Database.tech_nodes.values():
		if unlocked.has(node.id):
			continue
		var ready := true
		for parent_id in node.parents:
			if not unlocked.has(parent_id):
				ready = false
				break
		if ready:
			result.append(node.id)
	return result

func to_list() -> Array:
	return unlocked.keys()

func from_list(ids: Array) -> void:
	unlocked.clear()
	for id in ids:
		unlocked[StringName(id)] = true
