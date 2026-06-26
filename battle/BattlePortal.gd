class_name BattlePortal extends RefCounted
## A portal on the battlefield: it sits at one end of a row, emits its manifest one mech at a time,
## and can be destroyed. A wave ends when every enemy portal (and every enemy unit) is gone.

const PORTAL_HP := 150
const SPAWN_PERIOD := 1   # beats between emitting one mech

var team: int             # BattleUnit.PLAYER / ENEMY
var color: StringName     # which manifest this is (player side); enemy uses the same colors for tint
var tint: Color

var row: int
var col: int              # the cell mechs emerge on

var hp: int = PORTAL_HP
var max_hp: int = PORTAL_HP
var alive := true

var queue: Array = []     # remaining RobotLoadout to emit
var spawn_cd: int = 0

func has_pending() -> bool:
	return alive and not queue.is_empty()

func next_mech() -> RobotLoadout:
	return queue.pop_front()

func hurt(amount: int, _from_ranged: bool) -> void:
	hp -= amount   # portals have no shield
	if hp <= 0:
		alive = false
