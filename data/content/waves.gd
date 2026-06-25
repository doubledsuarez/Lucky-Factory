extends RefCounted
## Enemy waves, generated from a difficulty curve over every robot build the parts allow.
## Wave 1 is a swarm of the weakest builds; each wave is ~GROWTH stronger than the last; no more
## than MAX_SAME of any one build shows up; long-range builds stay out until RIFLE_UNLOCK_WAVE.
## Knobs are right here -- tweak and the whole curve regenerates off the current part stats.

const WAVE_COUNT := 20
const FIRST_WAVE_ROBOTS := 10     # size of wave 1 (built from the weakest combos)
const GROWTH := 1.2               # power multiplier per wave
const MAX_SAME := 3               # copies of one build allowed per wave
const RIFLE_UNLOCK_WAVE := 5      # long-range builds are held back until this wave
const LONG_RANGE := 5.0           # arms whose range is over this count as long range

static func register(database) -> void:
	var combos := _ranked_combos(database)
	if combos.is_empty():
		return
	var base: float = float(combos[0].power) * FIRST_WAVE_ROBOTS
	for index in range(1, WAVE_COUNT + 1):
		database.add_wave(_build_wave(index, combos, base))

# every legs/torso/head/arms combination with its power, weakest first
static func _ranked_combos(database) -> Array:
	var legs := _parts(database, ItemDef.Slot.LEGS)
	var torsos := _parts(database, ItemDef.Slot.TORSO)
	var heads := _parts(database, ItemDef.Slot.HEAD)
	var arms := _parts(database, ItemDef.Slot.ARMS)
	var combos := []
	for leg in legs:
		for torso in torsos:
			for head in heads:
				for arm in arms:
					var loadout := RobotLoadout.new()
					loadout.legs = leg
					loadout.torso = torso
					loadout.head = head
					loadout.arms = arm
					combos.append({ "loadout": loadout, "power": loadout.power() })
	combos.sort_custom(func(x, y): return x.power < y.power)
	return combos

static func _parts(database, slot: int) -> Array:
	var result := []
	for item in database.items.values():
		if item.slot == slot:
			result.append(item)
	return result

static func _build_wave(index: int, combos: Array, base: float) -> WaveDef:
	var target := base * pow(GROWTH, index - 1)
	# hold long-range builds back in the early waves
	var pool := []
	for combo in combos:
		if index < RIFLE_UNLOCK_WAVE and combo.loadout.attack_range() > LONG_RANGE:
			continue
		pool.append(combo)
	# work outward from the build power that suits this wave, taking up to MAX_SAME of each
	var center := int(round(lerpf(0.0, float(pool.size() - 1), float(index - 1) / float(WAVE_COUNT - 1))))
	var order := []
	for i in range(pool.size()):
		order.append(i)
	order.sort_custom(func(a, b): return absi(a - center) < absi(b - center))
	var squads := []
	var power := 0.0
	for i in order:
		if power >= target:
			break
		var combo = pool[i]
		var combo_power: float = combo.power
		var copies: int = clampi(int(ceil((target - power) / combo_power)), 1, MAX_SAME)
		power += copies * combo_power
		squads.append(_squad(combo.loadout, copies))
	var wave := WaveDef.new()
	wave.index = index
	wave.squads = squads
	wave.intel = _intel(squads)
	return wave

static func _squad(loadout: RobotLoadout, count: int) -> EnemySquad:
	var squad := EnemySquad.new()
	squad.legs = loadout.legs.id
	squad.torso = loadout.torso.id
	squad.head = loadout.head.id
	squad.arms = loadout.arms.id
	squad.count = count
	return squad

# a one-line build hint from the wave's dominant weapon and how armored it is
static func _intel(squads: Array) -> String:
	var reach := {}
	var armored := 0
	var total := 0
	for squad in squads:
		var arms_id := String(squad.arms)
		var kind := "fists"
		if arms_id.ends_with("rifle"):
			kind = "rifle"
		elif arms_id.ends_with("spear"):
			kind = "spear"
		reach[kind] = reach.get(kind, 0) + squad.count
		if String(squad.head).begins_with("scrap_boxer") or String(squad.torso).begins_with("scrap_boxer"):
			armored += squad.count
		total += squad.count
	var dominant := "fists"
	var best := 0
	for kind in reach:
		if reach[kind] > best:
			best = reach[kind]
			dominant = kind
	var line := ""
	match dominant:
		"rifle": line = "Long-range rifles -- they chip you on the approach. Bring armor and close fast."
		"spear": line = "Mid-range spears that hit hard. Out-range them or out-tank them."
		_: line = "Close-range brawlers. They have to reach you first."
	if total > 0 and armored * 2 >= total:
		line += " Heavily armored."
	return line
