class_name WaveDef extends RefCounted
## One enemy wave: the squads that show up, plus a one-line intel hint for the player.
## Waves run back to back in battle, so this only describes who's in each one, not any timing.

var index: int = 0
var intel: String = ""           # build hint shown in the briefing dialog
var squads: Array = []           # of EnemySquad

# expand the squads into the flat list of enemy robots for the battle (Array of RobotLoadout)
func loadouts() -> Array:
	var result: Array = []
	for squad in squads:
		for _copy in range(squad.count):
			result.append(squad.to_loadout())
	return result

func total_count() -> int:
	var total := 0
	for squad in squads:
		total += squad.count
	return total
