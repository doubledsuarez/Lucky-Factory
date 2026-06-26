class_name BattleSim extends RefCounted
## The deterministic heart of the battle. No drawing, no nodes -- just a grid of rows, two teams of
## units, and the portals they spawn from. Drive it by calling step() on the beat clock; read units /
## portals to render and won()/is_over() to finish. Built headless-testable on purpose.
##
## Beat clock: every step is a half-beat. Even half-beats are MOVE phases (mechs march one cell and
## portals emit), odd half-beats are FIRE phases (weapons discharge). So things move on the beat and
## shoot on the off-beat, like Attactics keeping time to the song.

const ROWS := 5
const COLS := 12
const PLAYER_COL := 0
const ENEMY_COL := COLS - 1
const MAX_HALF_BEATS := 4000   # safety cap so a stuck fight still resolves

var units: Array = []          # BattleUnit, both teams
var portals: Array = []        # BattlePortal, both teams
var half_beat := 0
var outcome := 0               # 0 ongoing, 1 player win, -1 player loss
var enemy_tint := Color(0.85, 0.25, 0.25)
# ranged shots fired on the latest step, for the renderer's tracers. each: { from, to, team } in
# cell space (Vector2(col, row)). cleared at the top of every step.
var recent_shots: Array = []

# placements: Array of { color, tint, row, manifest:Array[RobotLoadout] } for the player's portals.
# enemy_loadouts: the wave, expanded; spread round-robin across the rows as enemy portals.
func setup(placements: Array, enemy_loadouts: Array) -> void:
	units.clear()
	portals.clear()
	half_beat = 0
	outcome = 0
	for placement in placements:
		var manifest: Array = placement.get("manifest", [])
		if manifest.is_empty():
			continue   # a placed-but-empty portal has nothing to give; skip it
		var portal := BattlePortal.new()
		portal.team = BattleUnit.PLAYER
		portal.color = placement.get("color", &"blue")
		portal.tint = placement.get("tint", Color.WHITE)
		portal.row = int(placement.get("row", 0))
		portal.col = PLAYER_COL
		portal.queue = manifest.duplicate()
		portals.append(portal)
	_build_enemy_portals(enemy_loadouts)

func _build_enemy_portals(enemy_loadouts: Array) -> void:
	if enemy_loadouts.is_empty():
		return
	var by_row: Array = []
	for _r in range(ROWS):
		by_row.append([])
	for i in range(enemy_loadouts.size()):
		by_row[i % ROWS].append(enemy_loadouts[i])
	for r in range(ROWS):
		if by_row[r].is_empty():
			continue
		var portal := BattlePortal.new()
		portal.team = BattleUnit.ENEMY
		portal.color = &"enemy"
		portal.tint = enemy_tint
		portal.row = r
		portal.col = ENEMY_COL
		portal.queue = by_row[r]
		portals.append(portal)

func is_over() -> bool:
	return outcome != 0

func won() -> bool:
	return outcome == 1

func step() -> void:
	if outcome != 0:
		return
	recent_shots.clear()
	if half_beat % 2 == 0:
		_move_phase()
	else:
		_fire_phase()
	_cull()
	_resolve()
	half_beat += 1
	if outcome == 0 and half_beat >= MAX_HALF_BEATS:
		_resolve_timeout()

# --- phases ---

func _move_phase() -> void:
	var movers := units.duplicate()   # snapshot: mechs spawned this beat wait until the next one
	_spawn_phase()
	for unit in movers:
		_unit_move(unit)

# everyone fires off the same snapshot, then damage lands together -- so a duel resolves the same way
# no matter which side a mech is on (no first-mover kill advantage), and trades can be mutual
func _fire_phase() -> void:
	var shots: Array = []
	for unit in units:
		if not unit.alive:
			continue
		if unit.fire_cd > 0:
			unit.fire_cd -= 1
			continue
		var target = _nearest_enemy_in_row(unit, unit.row)
		if target == null or not _in_range(unit, target):
			continue   # nothing to shoot; stay primed so we fire the instant something steps up
		shots.append([target, unit.damage, unit.ranged])
		unit.fire_cd = unit.fire_period
		if unit.ranged:   # only rifles get a visible tracer
			recent_shots.append({
				"from": Vector2(unit.col, unit.row),
				"to": Vector2(target.col, target.row),
				"team": unit.team,
			})
	for shot in shots:
		shot[0].hurt(shot[1], shot[2])

func _spawn_phase() -> void:
	for portal in portals:
		if not portal.alive:
			continue
		if portal.spawn_cd > 0:
			portal.spawn_cd -= 1
			continue
		if not portal.has_pending():
			continue
		if _unit_at(portal.row, portal.col) != null:
			continue   # the mouth is blocked; hold the line until it clears
		var unit := BattleUnit.spawn(portal.next_mech(), portal.team, portal.row, portal.col)
		units.append(unit)
		portal.spawn_cd = BattlePortal.SPAWN_PERIOD

func _unit_move(unit: BattleUnit) -> void:
	if not unit.alive:
		return
	if unit.move_cd > 0:
		unit.move_cd -= 1
		return
	var target = _nearest_enemy_in_row(unit, unit.row)
	if target != null and _in_range(unit, target):
		return   # in reach -> stand and let the fire phase handle it (riflemen "hold if enemy in row")
	if target != null:
		_advance(unit)
		return
	# our row is clear: swarm toward the nearest row that still has enemies. the vertical hop ignores
	# friendly occupancy on purpose -- if it blocked, a wall of mechs stacked at the last column would
	# mutually block each other and the whole line would deadlock. they spread back out as they queue
	# along the new row (horizontal moves still respect occupancy).
	var swarm_row := _nearest_enemy_row(unit)
	if swarm_row == -1:
		return
	if swarm_row != unit.row:
		unit.row += signi(swarm_row - unit.row)
		unit.move_cd = unit.move_period
		return
	_advance(unit)

func _advance(unit: BattleUnit) -> void:
	var next_col := unit.col + unit.forward
	if next_col < 0 or next_col >= COLS:
		return
	if _cell_free(unit.row, next_col, unit):
		unit.col = next_col
		unit.move_cd = unit.move_period

# --- queries ---

func _nearest_enemy_in_row(unit: BattleUnit, row: int):
	var best = null
	var best_dist := 1 << 30
	for other in units:
		if not other.alive or other.team == unit.team or other.row != row:
			continue
		var dist: int = absi(other.col - unit.col)
		if dist < best_dist:
			best_dist = dist
			best = other
	for portal in portals:
		if not portal.alive or portal.team == unit.team or portal.row != row:
			continue
		var dist: int = absi(portal.col - unit.col)
		if dist < best_dist:
			best_dist = dist
			best = portal
	return best

func _in_range(unit: BattleUnit, target) -> bool:
	return absi(target.col - unit.col) <= unit.range_cells

# nearest row (by index distance) that still holds an enemy unit or a live enemy portal. ties are
# split by the unit's column so a stalled line fans out -- half head up, half head down -- instead of
# everyone funneling into the same row and piling up.
func _nearest_enemy_row(unit: BattleUnit) -> int:
	var best := -1
	var best_score := INF
	var prefer_down := (unit.col % 2 == 0)
	for row in range(ROWS):
		if not _row_has_enemy(unit.team, row):
			continue
		var score := float(absi(row - unit.row))
		if row != unit.row and (row > unit.row) != prefer_down:
			score += 0.25   # nudge against the non-preferred direction on a tie
		if score < best_score:
			best_score = score
			best = row
	return best

func _row_has_enemy(team: int, row: int) -> bool:
	for other in units:
		if other.alive and other.team != team and other.row == row:
			return true
	for portal in portals:
		if portal.alive and portal.team != team and portal.row == row:
			return true
	return false

func _cell_free(row: int, col: int, mover: BattleUnit) -> bool:
	for other in units:
		if other.alive and other != mover and other.row == row and other.col == col:
			return false
	return true

func _unit_at(row: int, col: int):
	for other in units:
		if other.alive and other.row == row and other.col == col:
			return other
	return null

# --- bookkeeping ---

func _cull() -> void:
	units = units.filter(func(u): return u.alive)
	portals = portals.filter(func(p): return p.alive)

func _resolve() -> void:
	var player_units := 0
	var enemy_units := 0
	var enemy_portals := false
	var player_can_spawn := false
	for unit in units:
		if unit.team == BattleUnit.PLAYER:
			player_units += 1
		else:
			enemy_units += 1
	for portal in portals:
		if portal.team == BattleUnit.ENEMY:
			enemy_portals = true
		elif portal.has_pending():
			player_can_spawn = true
	if enemy_units == 0 and not enemy_portals:
		outcome = 1
	elif player_units == 0 and not player_can_spawn:
		outcome = -1

func _resolve_timeout() -> void:
	outcome = 1 if _team_hp(BattleUnit.PLAYER) >= _team_hp(BattleUnit.ENEMY) else -1

func _team_hp(team: int) -> int:
	var total := 0
	for unit in units:
		if unit.team == team:
			total += unit.hp
	for portal in portals:
		if portal.team == team:
			total += portal.hp
	return total

# --- results ---

# survivors = player mechs still standing, plus any never deployed (still queued in a live portal)
func player_survivors() -> Array:
	var out: Array = []
	for unit in units:
		if unit.team == BattleUnit.PLAYER and unit.alive:
			out.append(unit.loadout)
	for portal in portals:
		if portal.team == BattleUnit.PLAYER:
			out.append_array(portal.queue)
	return out
