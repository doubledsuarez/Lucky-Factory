class_name BattleRenderer extends RefCounted
## All of the battle's drawing, kept out of Battle.gd the way FactoryRenderer is kept out of Factory.
## Everything is placeholder shapes: rows are bands, portals are tinted slabs, mechs are little shapes
## (square brawler / triangle spearman / circle rifleman) colored by side. Battle._draw() calls draw().

const PLAYER_TINT := Color(0.35, 0.6, 1.0)
const ENEMY_TINT := Color(0.9, 0.35, 0.3)
const ROW_A := Color(0.16, 0.17, 0.22)
const ROW_B := Color(0.13, 0.14, 0.18)
const GRID_LINE := Color(1, 1, 1, 0.07)
const HOVER_TINT := Color(1, 1, 1, 0.10)
const BACKDROP := Color(0.05, 0.06, 0.09)

static func draw(battle) -> void:
	# opaque backdrop first -- it hides the paused factory behind the overlay, and because _draw runs
	# before child controls, the hotbar/buttons still sit on top of it
	battle.draw_rect(Rect2(Vector2.ZERO, battle.size), BACKDROP)
	var field: Rect2 = battle.field_rect()
	var rows: int = BattleSim.ROWS
	var cols: int = BattleSim.COLS
	var cw: float = field.size.x / cols
	var ch: float = field.size.y / rows
	var font: Font = ThemeDB.fallback_font

	# row bands + the hovered row during deploy
	for r in range(rows):
		var band := Rect2(field.position + Vector2(0, r * ch), Vector2(field.size.x, ch))
		battle.draw_rect(band, ROW_A if r % 2 == 0 else ROW_B)
		if battle.state == battle.State.DEPLOY and r == battle.hovered_row and battle.selected_color != &"":
			battle.draw_rect(band, HOVER_TINT)
	# column guides
	for c in range(cols + 1):
		var x: float = field.position.x + c * cw
		battle.draw_line(Vector2(x, field.position.y), Vector2(x, field.position.y + field.size.y), GRID_LINE)
	battle.draw_rect(field, Color(1, 1, 1, 0.15), false, 2.0)

	if battle.state == battle.State.DEPLOY:
		_draw_deploy(battle, field, cw, ch, font)
	else:
		_draw_sim(battle, field, cw, ch, font)
		_draw_projectiles(battle, field, cw, ch)

static func _cell_center(field: Rect2, cw: float, ch: float, row: int, col: int) -> Vector2:
	return field.position + Vector2((col + 0.5) * cw, (row + 0.5) * ch)

static func _draw_deploy(battle, field: Rect2, cw: float, ch: float, font: Font) -> void:
	# show the player's placed portals on the left of their chosen rows
	for color in battle.row_for_color:
		var row: int = battle.row_for_color[color]
		var tint: Color = battle.color_tints.get(color, Color.WHITE)
		var count: int = Run.manifest(color).size()
		_draw_portal_slab(battle, _cell_center(field, cw, ch, row, 0), cw, ch, tint, "%d" % count, font)
	# the enemy edge marker
	var right := field.position.x + field.size.x
	battle.draw_string(font, Vector2(right - 90, field.position.y - 8), "ENEMY ▶", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, ENEMY_TINT)
	battle.draw_string(font, Vector2(field.position.x, field.position.y - 8), "◀ YOUR PORTALS", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, PLAYER_TINT)

static func _draw_sim(battle, field: Rect2, cw: float, ch: float, font: Font) -> void:
	var sim: BattleSim = battle.sim
	if sim == null:
		return
	# portals
	for portal in sim.portals:
		var tint: Color = portal.tint if portal.team == BattleUnit.PLAYER else ENEMY_TINT
		var center := _cell_center(field, cw, ch, portal.row, portal.col)
		_draw_portal_slab(battle, center, cw, ch, tint, "", font)
		_draw_hp_bar(battle, center, cw, ch * 0.5, float(portal.hp) / float(portal.max_hp), tint)
	# units
	for unit in sim.units:
		var center := _cell_center(field, cw, ch, unit.row, unit.col)
		var tint: Color = PLAYER_TINT if unit.team == BattleUnit.PLAYER else ENEMY_TINT
		_draw_unit(battle, center, cw, ch, unit, tint)
		_draw_hp_bar(battle, center, cw * 0.7, ch * 0.5, float(unit.hp) / float(unit.max_hp), tint)

# rifle tracers: a little bolt sliding from shooter toward target, with a faint trail behind it
static func _draw_projectiles(battle, field: Rect2, cw: float, ch: float) -> void:
	for projectile in battle.projectiles:
		var t: float = clampf(projectile.age / battle.PROJECTILE_LIFE, 0.0, 1.0)
		var from_px := _cell_center(field, cw, ch, int(projectile.from.y), int(projectile.from.x))
		var to_px := _cell_center(field, cw, ch, int(projectile.to.y), int(projectile.to.x))
		var head := from_px.lerp(to_px, t)
		var tail := from_px.lerp(to_px, maxf(t - 0.18, 0.0))
		var tint: Color = PLAYER_TINT if projectile.team == BattleUnit.PLAYER else ENEMY_TINT
		battle.draw_line(tail, head, Color(tint, 0.45), 2.0)
		battle.draw_circle(head, minf(cw, ch) * 0.09, tint.lightened(0.4))

static func _draw_portal_slab(battle, center: Vector2, cw: float, ch: float, tint: Color, label: String, font: Font) -> void:
	var size := Vector2(cw * 0.8, ch * 0.8)
	var rect := Rect2(center - size * 0.5, size)
	battle.draw_rect(rect, tint.darkened(0.2))
	battle.draw_rect(rect, tint.lightened(0.3), false, 2.0)
	if label != "":
		battle.draw_string(font, center + Vector2(-6, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

static func _draw_unit(battle, center: Vector2, cw: float, ch: float, unit, tint: Color) -> void:
	var radius: float = minf(cw, ch) * 0.32
	match unit.classification:
		"rifleman":
			battle.draw_circle(center, radius, tint)
		"spearman":
			var pts := PackedVector2Array([
				center + Vector2(0, -radius),
				center + Vector2(radius, radius),
				center + Vector2(-radius, radius)])
			battle.draw_colored_polygon(pts, tint)
		_:  # brawler -- square, with a shield tick if it carries one
			var s := Vector2(radius, radius) * 1.6
			battle.draw_rect(Rect2(center - s * 0.5, s), tint)
			if unit.shield > 0:
				battle.draw_rect(Rect2(center - s * 0.5, s), Color.WHITE, false, 2.0)

static func _draw_hp_bar(battle, center: Vector2, width: float, y_off: float, frac: float, tint: Color) -> void:
	frac = clampf(frac, 0.0, 1.0)
	var bar_h := 3.0
	var top_left := center + Vector2(-width * 0.5, -y_off)
	battle.draw_rect(Rect2(top_left, Vector2(width, bar_h)), Color(0, 0, 0, 0.6))
	battle.draw_rect(Rect2(top_left, Vector2(width * frac, bar_h)), tint.lightened(0.2))
