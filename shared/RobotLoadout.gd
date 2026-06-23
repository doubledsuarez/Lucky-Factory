class_name RobotLoadout extends RefCounted
## A built robot: the four parts it was assembled from. Stats and looks derive from these.

var legs: ItemDef
var torso: ItemDef
var head: ItemDef
var arms: ItemDef

func signature() -> String:
	return "%s|%s|%s|%s" % [legs.id, torso.id, head.id, arms.id]

# how the four parts combine into a robot's stats -- the single source both the
# shuttle UI and the battle read, so any combination resolves the same way
func total_armor() -> int:
	return head.armor + torso.armor + legs.armor + arms.armor

func move_speed() -> float:
	return legs.speed * torso.speed   # legs drive it, torso scales it

func turn_rate() -> float:
	return torso.turn_rate

func damage() -> int:
	return arms.damage

func attack_range() -> float:
	return arms.attack_range

func attack_speed() -> float:
	return arms.attack_speed

# a single combat-strength number, used to compare armies on the reward screen (tunable)
func power() -> float:
	return float(total_armor()) + float(damage()) * maxf(attack_speed(), 0.1)
