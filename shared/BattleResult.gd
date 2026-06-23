class_name BattleResult extends RefCounted
## What the battle phase hands back. The reward screen derives everything else (power, card count) from this.

var won := false
var sent: Array = []        # RobotLoadout the player sent into the fight
var survivors: Array = []   # RobotLoadout still alive afterward
var enemies: Array = []     # RobotLoadout in the wave they had to defeat

func sent_power() -> float:
	return _power(sent)

func survivor_power() -> float:
	return _power(survivors)

func enemy_power() -> float:
	return _power(enemies)

func _power(army: Array) -> float:
	var total := 0.0
	for loadout in army:
		total += loadout.power()
	return total
