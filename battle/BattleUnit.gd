class_name BattleUnit extends RefCounted
## One mech on the battlefield. Wraps a RobotLoadout and tracks where it is, what's left of it, and
## when it may next move or fire. All combat numbers come straight off the loadout -- the battle only
## decides the cadence and turns the float stats into grid cells.

const PLAYER := 0
const ENEMY := 1

# how many beats a unit waits between steps / shots before its speed stats scale it. Higher = slower.
# move is tuned so a quick mech steps every beat and the heavy boxer every other -- watchable at 1x.
const BASE_MOVE_BEATS := 1.0
const BASE_FIRE_BEATS := 2.0
const FULL_LANE := 99   # rifles reach the whole row

var loadout: RobotLoadout
var team: int
var classification: String   # "brawler" / "spearman" / "rifleman" -- display + flavor

var row: int
var col: int
var forward: int             # +1 for the player (marching right), -1 for the enemy

var hp: int
var max_hp: int
var damage: int
var shield_max: int          # the shield's durability when fresh (0 for non-shield mechs)
var shield_hp: int           # remaining shield; blocks ranged fire while > 0, battered down by melee
var ranged: bool             # rifles; the only thing a shield blocks
var range_cells: int

var move_period: int         # beats between steps
var fire_period: int         # off-beats between shots
var move_cd: int = 0
var fire_cd: int = 0

var alive := true

static func classify(build: RobotLoadout) -> String:
	var arms_id := String(build.arms.id)
	if arms_id.ends_with("rifle"):
		return "rifleman"
	if arms_id.ends_with("spear"):
		return "spearman"
	return "brawler"

static func spawn(build: RobotLoadout, unit_team: int, unit_row: int, unit_col: int) -> BattleUnit:
	var unit := BattleUnit.new()
	unit.loadout = build
	unit.team = unit_team
	unit.forward = 1 if unit_team == PLAYER else -1
	unit.classification = classify(build)
	unit.max_hp = maxi(1, build.total_armor())
	unit.hp = unit.max_hp
	unit.damage = maxi(1, build.damage())
	unit.shield_max = build.shield_value()
	unit.shield_hp = unit.shield_max
	unit.ranged = build.is_ranged()
	unit.range_cells = _range_cells(build.attack_range())
	unit.move_period = maxi(1, int(round(BASE_MOVE_BEATS / maxf(build.move_speed(), 0.1))))
	unit.fire_period = maxi(1, int(round(BASE_FIRE_BEATS / maxf(build.attack_speed(), 0.1))))
	unit.row = unit_row
	unit.col = unit_col
	return unit

# float reach -> grid cells: fists adjacent (1), spears two away (2), rifles the whole lane
static func _range_cells(reach: float) -> int:
	if reach <= 1.0:
		return 1
	if reach <= RobotLoadout.LONG_RANGE - 0.001:
		return 2
	return FULL_LANE

# take a hit. while the shield holds it stops ranged fire outright -- arrows can't get through it. melee
# always lands on the body in full AND batters the shield down; once the shield is gone the mech is
# exposed to ranged fire for the rest of the fight (it doesn't come back).
func hurt(amount: int, from_ranged: bool) -> void:
	if from_ranged:
		if shield_hp > 0:
			return   # arrow stopped cold by the shield; fire doesn't wear the shield down, only melee does
		hp -= amount
	else:
		hp -= amount
		shield_hp = maxi(0, shield_hp - amount)
	if hp <= 0:
		alive = false
