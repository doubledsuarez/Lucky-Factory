extends Node
## Throwaway headless harness: godot --headless res://battle/_test_sim.tscn
## Verifies the sim terminates and the rock-paper-scissors triangle holds in clean 1v1 duels.

func _build(legs: StringName, torso: StringName, head: StringName, arms: StringName) -> RobotLoadout:
	var lo := RobotLoadout.new()
	lo.legs = Database.item(legs)
	lo.torso = Database.item(torso)
	lo.head = Database.item(head)
	lo.arms = Database.item(arms)
	return lo

func _boxer() -> RobotLoadout:
	return _build(&"scrap_boxer_legs", &"scrap_boxer_torso", &"scrap_boxer_head", &"scrap_boxer_fists")

func _hunter() -> RobotLoadout:
	return _build(&"scrap_hunter_legs", &"scrap_hunter_torso", &"scrap_hunter_head", &"scrap_hunter_rifle")

func _warrior() -> RobotLoadout:
	return _build(&"scrap_warrior_legs", &"scrap_warrior_torso", &"scrap_warrior_head", &"scrap_warrior_spear")

# run a clean 1v1: player build vs enemy build, no portals. returns +1 player win, -1 loss.
func _duel(player_build: RobotLoadout, enemy_build: RobotLoadout) -> int:
	var sim := BattleSim.new()
	sim.units.append(BattleUnit.spawn(player_build, BattleUnit.PLAYER, 0, BattleSim.PLAYER_COL))
	sim.units.append(BattleUnit.spawn(enemy_build, BattleUnit.ENEMY, 0, BattleSim.ENEMY_COL))
	var guard := 0
	while not sim.is_over() and guard < 10000:
		sim.step()
		guard += 1
	return sim.outcome

func _report(name: String, result: int, expect: int) -> bool:
	var ok := result == expect
	print("  %-26s -> %s (expected %s)  %s" % [name, result, expect, "OK" if ok else "FAIL"])
	return ok

func _ready() -> void:
	print("== stat sanity ==")
	for b in [["boxer", _boxer()], ["hunter", _hunter()], ["warrior", _warrior()]]:
		var lo: RobotLoadout = b[1]
		print("  %-7s hp=%d dmg=%d range=%.0f shield=%d ranged=%s power=%.1f" % [
			b[0], lo.total_armor(), lo.damage(), lo.attack_range(), lo.shield_value(), lo.is_ranged(), lo.power()])

	print("== RPS duels (player listed first should win) ==")
	var all_ok := true
	all_ok = _report("brawler vs rifleman", _duel(_boxer(), _hunter()), 1) and all_ok
	all_ok = _report("rifleman vs spearman", _duel(_hunter(), _warrior()), 1) and all_ok
	all_ok = _report("spearman vs brawler", _duel(_warrior(), _boxer()), 1) and all_ok
	all_ok = _report("rifleman vs brawler", _duel(_hunter(), _boxer()), -1) and all_ok
	all_ok = _report("spearman vs rifleman", _duel(_warrior(), _hunter()), -1) and all_ok
	all_ok = _report("brawler vs spearman", _duel(_boxer(), _warrior()), -1) and all_ok

	print("== full wave (blue manifest of mixed mechs vs wave 3) ==")
	var manifest := [_boxer(), _boxer(), _warrior(), _hunter(), _hunter()]
	var placements := [{ "color": &"blue", "tint": Color.BLUE, "row": 2, "manifest": manifest }]
	var wave := Database.wave(3)
	var enemies: Array = wave.loadouts() if wave != null else []
	var sim := BattleSim.new()
	sim.setup(placements, enemies)
	var guard := 0
	while not sim.is_over() and guard < 20000:
		sim.step()
		guard += 1
	print("  enemies=%d  resolved in %d half-beats  outcome=%d  survivors=%d" % [
		enemies.size(), sim.half_beat, sim.outcome, sim.player_survivors().size()])

	print("RESULT: %s" % ("ALL OK" if all_ok else "FAILURES ABOVE"))
	get_tree().quit()
