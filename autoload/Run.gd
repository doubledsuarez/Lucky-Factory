extends Node
## Carries the built army from the factory to the battle. Robots load into one of five portal
## manifests (by color); the battle reads these and clears them once rewards are tallied.

const PORTAL_COLORS: Array[StringName] = [&"blue", &"green", &"red", &"orange", &"yellow"]

var portal_manifests: Dictionary = {}   # color -> Array of RobotLoadout

func _ready() -> void:
	for color in PORTAL_COLORS:
		portal_manifests[color] = []

func load_robot(color: StringName, loadout: RobotLoadout) -> void:
	if not portal_manifests.has(color):
		portal_manifests[color] = []
	portal_manifests[color].append(loadout)

func manifest(color: StringName) -> Array:
	return portal_manifests.get(color, [])

# every loaded robot across all portals -- the combined army, for sent power and the result
func all_robots() -> Array:
	var combined: Array = []
	for color in PORTAL_COLORS:
		combined.append_array(portal_manifests.get(color, []))
	return combined

func total_robots() -> int:
	var total := 0
	for color in PORTAL_COLORS:
		total += portal_manifests.get(color, []).size()
	return total

func clear_manifests() -> void:
	for color in PORTAL_COLORS:
		portal_manifests[color] = []
