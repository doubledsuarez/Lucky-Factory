extends Control
## Battle playground -- run this scene directly (F6 in the editor, or the command below) to jump
## straight into the deploy screen with a ready-made army, no factory grind needed:
##   godot res://battle/Sandbox.tscn
## Pick portals onto rows, press Fight, watch it play. When it ends it re-seeds and loops so you can
## keep iterating. Esc quits. Change WAVE to face a different enemy wave.

const WAVE := 5   # wave 5+ includes long-range rifles, so you get the full rock-paper-scissors

var _battle: Battle

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Unlocks.unlock_all()   # all five portal colors available to place
	_new_battle()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_tree().quit()

func _new_battle() -> void:
	_seed_army()
	_battle = preload("res://battle/Battle.tscn").instantiate()
	_battle.setup(WAVE)
	_battle.finished.connect(_on_finished)
	add_child(_battle)

# fill every portal manifest with a small mixed squad so the hotbar has all five colors to place
func _seed_army() -> void:
	Run.clear_manifests()
	var roster := {
		&"blue": [&"boxer", &"boxer", &"boxer", &"boxer"],
		&"green": [&"hunter", &"hunter", &"hunter"],
		&"red": [&"warrior", &"warrior", &"warrior"],
		&"orange": [&"boxer", &"warrior"],
		&"yellow": [&"hunter", &"hunter"],
	}
	for color in roster:
		for kind in roster[color]:
			Run.load_robot(color, _build(kind))

func _on_finished(result: BattleResult) -> void:
	print("battle over: won=%s  survivors=%d / %d" % [result.won, result.survivors.size(), result.sent.size()])
	_battle.queue_free()
	_new_battle()   # loop back into a fresh deploy so you can test again

func _build(kind: StringName) -> RobotLoadout:
	var lo := RobotLoadout.new()
	match kind:
		&"hunter":
			lo.legs = Database.item(&"scrap_hunter_legs"); lo.torso = Database.item(&"scrap_hunter_torso")
			lo.head = Database.item(&"scrap_hunter_head"); lo.arms = Database.item(&"scrap_hunter_rifle")
		&"warrior":
			lo.legs = Database.item(&"scrap_warrior_legs"); lo.torso = Database.item(&"scrap_warrior_torso")
			lo.head = Database.item(&"scrap_warrior_head"); lo.arms = Database.item(&"scrap_warrior_spear")
		_:
			lo.legs = Database.item(&"scrap_boxer_legs"); lo.torso = Database.item(&"scrap_boxer_torso")
			lo.head = Database.item(&"scrap_boxer_head"); lo.arms = Database.item(&"scrap_boxer_fists")
	return lo
