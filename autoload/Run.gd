extends Node
## Carries the built army from the factory to the battle across the scene change.

# robots loaded on the shuttle during the factory phase
var shuttle_robots: Array[RobotLoadout] = []
# the army handed to the battle phase when the shuttle launches; the battle scene reads this
var launched_robots: Array[RobotLoadout] = []

func load_robot(loadout: RobotLoadout) -> void:
	shuttle_robots.append(loadout)

func reset_shuttle() -> void:
	shuttle_robots.clear()

# snapshot the loaded robots as the battle army and clear the shuttle for the next round
func launch_shuttle() -> Array[RobotLoadout]:
	launched_robots = shuttle_robots.duplicate()
	shuttle_robots.clear()
	return launched_robots
