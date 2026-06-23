extends RefCounted
## Crafting machines: forge (scrap to ingots), crafter (ingots to parts), assembler (parts to robots).

const RIGHT := MachineBuilders.RIGHT
const DOWN := MachineBuilders.DOWN
const LEFT := MachineBuilders.LEFT
const UP := MachineBuilders.UP
const INPUT := MachineBuilders.INPUT
const OUTPUT := MachineBuilders.OUTPUT

static func register(database) -> void:
	database.add_machine(_forge())
	database.add_machine(_crafter())
	database.add_machine(_assembler())

static func _forge() -> MachineDef:
	var def := MachineBuilders.machine(&"t1_forge", "T1 Forge", Color(0.80, 0.45, 0.20), MachineDef.Kind.CRAFTER)
	def.build_cost = 25
	def.recipe = MachineBuilders.recipe(&"scrap", 1, &"scrap_ingot", 1, 5.0)
	def.ports = [MachineBuilders.port(0, 0, LEFT, INPUT), MachineBuilders.port(0, 0, RIGHT, OUTPUT)]
	return def

static func _crafter() -> MachineDef:
	# 1 wide x 2 tall; item enters the bottom end, the part leaves the top end
	var def := MachineBuilders.machine(&"t1_crafter", "T1 Crafter", Color(0.45, 0.55, 0.35), MachineDef.Kind.CRAFTER)
	def.build_cost = 25
	def.footprint = Vector2i(1, 2)
	# placed empty; the player picks one of these from the machine panel before it will craft
	def.recipes = [
		MachineBuilders.recipe(&"scrap_ingot", 10, &"scrap_boxer_head", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 3, &"scrap_hunter_head", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 5, &"scrap_warrior_head", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 20, &"scrap_boxer_torso", 1, 6.0),
		MachineBuilders.recipe(&"scrap_ingot", 6, &"scrap_hunter_torso", 1, 6.0),
		MachineBuilders.recipe(&"scrap_ingot", 10, &"scrap_warrior_torso", 1, 6.0),
		MachineBuilders.recipe(&"scrap_ingot", 10, &"scrap_boxer_legs", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 3, &"scrap_hunter_legs", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 5, &"scrap_warrior_legs", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 10, &"scrap_boxer_fists", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 3, &"scrap_warrior_spear", 1, 3.0),
		MachineBuilders.recipe(&"scrap_ingot", 5, &"scrap_hunter_rifle", 1, 3.0),
	]
	def.ports = [MachineBuilders.port(0, 1, DOWN, INPUT), MachineBuilders.port(0, 0, UP, OUTPUT)]
	return def

static func _assembler() -> MachineDef:
	# 4x4; four part inputs along the bottom, the finished robot leaves the back (top)
	var def := MachineBuilders.machine(&"t1_assembler", "T1 Assembler", Color(0.55, 0.50, 0.75), MachineDef.Kind.ASSEMBLER)
	def.build_cost = 30
	def.footprint = Vector2i(4, 4)
	def.recipe = MachineBuilders.robot_recipe()
	def.ports = [
		MachineBuilders.port(0, 3, DOWN, INPUT),
		MachineBuilders.port(1, 3, DOWN, INPUT),
		MachineBuilders.port(2, 3, DOWN, INPUT),
		MachineBuilders.port(3, 3, DOWN, INPUT),
		MachineBuilders.port(1, 0, UP, OUTPUT),
	]
	return def
