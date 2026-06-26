class_name Battle extends Control
## The battle phase, run as a full-screen overlay over the factory. Reads the portal manifests and the
## current wave, lets the player drop their portals onto rows, then plays a beat-timed auto-battle and
## hands back a BattleResult. Drawing lives in BattleRenderer; this file owns state, input, and timing.

signal finished(result: BattleResult)

enum State { DEPLOY, FIGHTING, RESOLVED }

const BPM := 112.0                       # baked from assets/Lucky-Factory.mp3 (a live take; close enough)
const HALF_BEAT := 60.0 / BPM / 2.0      # seconds per half-beat: move on the beat, fire on the off-beat
const PROJECTILE_LIFE := 0.16            # seconds a rifle tracer takes to cross from shooter to target

var wave_index := 1
var state: State = State.DEPLOY
var sim: BattleSim

# deploy data
var color_tints: Dictionary = {}         # color -> Color
var row_for_color: Dictionary = {}       # color -> assigned row (the placement)
var selected_color: StringName = &""
var hovered_row := -1

var _accum := 0.0
var _result: BattleResult
var _music: AudioStreamPlayer
var projectiles: Array = []   # live rifle tracers: { from, to, team, age } (cell space)

@onready var _hint: Label = $Hint
@onready var _hotbar: HBoxContainer = $Bottom/Hotbar
@onready var _fight_button: Button = $Bottom/Fight
@onready var _speed_box: HBoxContainer = $Speed
@onready var _result_box: Control = $ResultBox

func setup(wave: int) -> void:
	wave_index = wave

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_load_colors()
	_init_deploy()
	_build_hotbar()
	_build_speed()
	_build_music()
	_fight_button.pressed.connect(_on_fight_pressed)
	_result_box.visible = false
	_refresh_hint()

func _load_colors() -> void:
	for color in Run.PORTAL_COLORS:
		var machine: MachineDef = Database.machine(StringName("portal_" + color))
		color_tints[color] = machine.color if machine != null else Color.WHITE

# auto-place every loaded portal on its own row so the fight is ready immediately; the player can
# still rearrange from the hotbar before pressing Fight
func _init_deploy() -> void:
	row_for_color.clear()
	var row := 0
	for color in Run.PORTAL_COLORS:
		if Run.manifest(color).is_empty():
			continue
		if row >= BattleSim.ROWS:
			break
		row_for_color[color] = row
		row += 1

func _placeable(color: StringName) -> bool:
	return not Run.manifest(color).is_empty()

# --- deploy UI ---

func _build_hotbar() -> void:
	for child in _hotbar.get_children():
		child.queue_free()
	for color in Run.PORTAL_COLORS:
		var button := Button.new()
		button.custom_minimum_size = Vector2(86, 44)
		var count := Run.manifest(color).size()
		button.text = "%s\n%d" % [String(color).capitalize(), count]
		button.add_theme_font_size_override("font_size", 12)
		button.disabled = not _placeable(color)
		button.modulate = color_tints.get(color, Color.WHITE)
		button.pressed.connect(_on_hotbar_pressed.bind(color))
		_hotbar.add_child(button)

func _on_hotbar_pressed(color: StringName) -> void:
	selected_color = color
	_refresh_hint()
	queue_redraw()

func _place(color: StringName, row: int) -> void:
	# one portal per row, one row per color: clear whatever shared either slot
	for other in row_for_color.keys():
		if row_for_color[other] == row:
			row_for_color.erase(other)
	row_for_color[color] = row
	queue_redraw()

func _build_speed() -> void:
	for speed in [1.0, 2.0, 4.0]:
		var button := Button.new()
		button.custom_minimum_size = Vector2(40, 28)
		button.text = "%dx" % int(speed)
		button.pressed.connect(func(): Sim.speed = speed)
		_speed_box.add_child(button)

# the song sets the tempo; it loops and rides Sim.speed so the beat stays roughly in time when sped up
func _build_music() -> void:
	var stream := load("res://assets/Lucky-Factory.mp3")
	if stream == null:
		return
	if stream is AudioStreamMP3:
		stream.loop = true
	_music = AudioStreamPlayer.new()
	_music.stream = stream
	add_child(_music)

func _refresh_hint() -> void:
	match state:
		State.DEPLOY:
			if selected_color == &"":
				_hint.text = "Wave %d — pick a portal, then click a row to place it. Press Fight when ready." % wave_index
			else:
				_hint.text = "Placing %s — click a row." % String(selected_color).capitalize()
		State.FIGHTING:
			_hint.text = "Wave %d — fight!" % wave_index
		State.RESOLVED:
			_hint.text = "Wave %d — %s" % [wave_index, "Victory!" if _result.won else "Defeated"]

func _gui_input(event: InputEvent) -> void:
	if state != State.DEPLOY:
		return
	var field := field_rect()
	if event is InputEventMouseMotion:
		hovered_row = _row_at(event.position, field)
		queue_redraw()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var row := _row_at(event.position, field)
		if row != -1 and selected_color != &"" and _placeable(selected_color):
			_place(selected_color, row)

func _row_at(pos: Vector2, field: Rect2) -> int:
	if not field.has_point(pos):
		return -1
	var ch := field.size.y / BattleSim.ROWS
	return clampi(int((pos.y - field.position.y) / ch), 0, BattleSim.ROWS - 1)

# the battlefield is a real grid drawn at the factory's cell scale, so a battle cell == a factory cell
# (one CELL_SIZE square). Reusing Factory.CELL_SIZE keeps both phases speaking the same grid and sets
# up the eventual one-map embed. Centered in the band between the title and the hotbar.
func field_rect() -> Rect2:
	var w := float(BattleSim.COLS * Factory.CELL_SIZE)
	var h := float(BattleSim.ROWS * Factory.CELL_SIZE)
	var top := 80.0
	var bottom_limit := size.y - 110.0
	var x := (size.x - w) * 0.5
	var y := top + ((bottom_limit - top) - h) * 0.5
	return Rect2(x, y, w, h)

# --- fight ---

func _on_fight_pressed() -> void:
	if row_for_color.is_empty():
		return
	_start_fight()

func _start_fight() -> void:
	var placements: Array = []
	for color in row_for_color:
		var manifest: Array = Run.manifest(color).duplicate()
		_apply_player_buffs(manifest)
		placements.append({
			"color": color,
			"tint": color_tints.get(color, Color.WHITE),
			"row": row_for_color[color],
			"manifest": manifest,
		})
	var wave: WaveDef = Database.wave(wave_index)
	var enemies: Array = wave.loadouts() if wave != null else []
	sim = BattleSim.new()
	sim.setup(placements, enemies)
	state = State.FIGHTING
	_accum = 0.0
	_hotbar.visible = false
	_fight_button.visible = false
	if _music != null:
		_music.play()
	_refresh_hint()
	queue_redraw()

# unlocked tech-tree buffs that affect combat get applied to the army here. none carry the
# "battle_buff" category yet (current buff nodes are factory-economy), so this loop is the
# extensible hook the plan calls for -- a new combat node just needs to set that category.
func _apply_player_buffs(_manifest: Array) -> void:
	for id in Unlocks.unlocked:
		var node: TechNode = Database.tech_node(id)
		if node == null or node.category != "battle_buff":
			continue
		# future: fold node's combat effect into each RobotLoadout in _manifest

func _process(delta: float) -> void:
	if state != State.FIGHTING or sim == null:
		return
	if _music != null:
		_music.pitch_scale = clampf(Sim.speed, 0.5, 3.0)
	var step_time := HALF_BEAT / maxf(Sim.speed, 0.05)
	_accum += delta
	var guard := 0
	while _accum >= step_time and not sim.is_over() and guard < 64:
		_accum -= step_time
		sim.step()
		for shot in sim.recent_shots:
			projectiles.append({ "from": shot.from, "to": shot.to, "team": shot.team, "age": 0.0 })
		guard += 1
	_age_projectiles(delta * maxf(Sim.speed, 0.05))
	queue_redraw()
	if sim.is_over():
		_finish()

# tracers age on the same clock as the sim, so they stay snappy when the fight is sped up
func _age_projectiles(amount: float) -> void:
	for projectile in projectiles:
		projectile.age += amount
	projectiles = projectiles.filter(func(p): return p.age < PROJECTILE_LIFE)

func _finish() -> void:
	state = State.RESOLVED
	projectiles.clear()
	if _music != null:
		_music.stop()
	_result = BattleResult.new()
	_result.won = sim.won()
	_result.sent = Run.all_robots()
	_result.survivors = sim.player_survivors()
	var wave: WaveDef = Database.wave(wave_index)
	_result.enemies = wave.loadouts() if wave != null else []
	_refresh_hint()
	_show_result()

func _show_result() -> void:
	_result_box.visible = true
	var label: Label = _result_box.get_node("Panel/Box/Label")
	var button: Button = _result_box.get_node("Panel/Box/Continue")
	label.text = "%s\nSurvivors: %d / %d" % [
		"VICTORY" if _result.won else "DEFEAT",
		_result.survivors.size(), _result.sent.size()]
	if not button.pressed.is_connected(_on_continue_pressed):
		button.pressed.connect(_on_continue_pressed)
	button.grab_focus()

func _on_continue_pressed() -> void:
	finished.emit(_result)

func _draw() -> void:
	BattleRenderer.draw(self)
