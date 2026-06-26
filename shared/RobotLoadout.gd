class_name RobotLoadout extends RefCounted
## A built robot: the four parts it was assembled from. Stats and looks derive from these.

# arms with reach past this count as long-range (rifles) -- the one threshold the wave generator
# and the battle's shield rule both read, so "ranged" means the same thing everywhere
const LONG_RANGE := 5.0

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

# flat damage soaked from each ranged hit (the boxer's shield); melee ignores it
func shield_value() -> int:
	return head.shield + torso.shield + legs.shield + arms.shield

# true for rifles -- long reach. the shield only blocks these; spears and fists punch through
func is_ranged() -> bool:
	return attack_range() >= LONG_RANGE

# combat-strength estimate for comparing armies (reward screen, wave ranking). armor for
# survivability, plus offense scaled by reach (free hits down the lane before contact) and
# mobility (closing, kiting, dodging approach hits). constants are tuned against the battle sim.
func power() -> float:
	var dps := float(damage()) * attack_speed()
	var reach := 1.0 + attack_range() * 0.1
	var mobility := 0.4 + 0.4 * move_speed() + 0.2 * turn_rate()
	return float(total_armor()) + dps * reach * mobility
