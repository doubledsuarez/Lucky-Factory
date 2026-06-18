extends RefCounted
## Every machine in the game. Add new ones here.

static func register(database) -> void:
	database.add_machine(_source(&"depo", "Depo", Color(0.35, 0.28, 0.18), &"scrap"))
	database.add_machine(_shuttle())
	database.add_machine(_forge())
	database.add_machine(_crafter())
	database.add_machine(_assembler())
	database.add_machine(_storage(&"bank", "Bank", Color(0.30, 0.45, 0.70), &"ingot", 100))

static func _forge() -> MachineDef:
	var def := MachineDef.new()
	def.id = &"forge"
	def.display_name = "Forge"
	def.color = Color(0.80, 0.45, 0.20)
	def.kind = MachineDef.Kind.CRAFTER
	def.build_cost = 25
	def.recipe = _recipe(&"scrap", 1, &"ingot", 1, 5.0)
	return def

static func _crafter() -> MachineDef:
	var def := MachineDef.new()
	def.id = &"crafter"
	def.display_name = "Crafter"
	def.color = Color(0.45, 0.55, 0.35)
	def.kind = MachineDef.Kind.CRAFTER
	def.build_cost = 25
	def.recipes = [
		_recipe(&"ingot", 5, &"part_head", 1, 3.0),
		_recipe(&"ingot", 10, &"part_torso", 1, 6.0),
		_recipe(&"ingot", 5, &"part_arms", 1, 3.0),
		_recipe(&"ingot", 5, &"part_legs", 1, 3.0),
	]
	def.recipe = def.recipes[0]
	return def

static func _assembler() -> MachineDef:
	var def := MachineDef.new()
	def.id = &"assembler"
	def.display_name = "Assembler"
	def.color = Color(0.55, 0.50, 0.75)
	def.kind = MachineDef.Kind.ASSEMBLER
	def.build_cost = 30
	def.recipe = _robot_recipe()
	return def

static func _shuttle() -> MachineDef:
	var def := MachineDef.new()
	def.id = &"shuttle"
	def.display_name = "Shuttle"
	def.color = Color(0.30, 0.35, 0.45)
	def.kind = MachineDef.Kind.SHUTTLE
	return def

static func _recipe(input_id: StringName, input_count: int, output_id: StringName, output_count: int, craft_time: float) -> Recipe:
	var recipe := Recipe.new()
	recipe.inputs = { input_id: input_count }
	recipe.output_id = output_id
	recipe.output_count = output_count
	recipe.craft_time = craft_time
	return recipe

static func _robot_recipe() -> Recipe:
	# the assembler builds from one of each part (handled in code), so no item inputs here
	var recipe := Recipe.new()
	recipe.output_id = &"robot"
	recipe.output_count = 1
	recipe.craft_time = 4.0
	return recipe

static func _source(id: StringName, display_name: String, color: Color, source_item: StringName) -> MachineDef:
	var def := MachineDef.new()
	def.id = id
	def.display_name = display_name
	def.color = color
	def.kind = MachineDef.Kind.SOURCE
	def.source_item = source_item
	return def

static func _storage(id: StringName, display_name: String, color: Color, storage_item: StringName, capacity: int) -> MachineDef:
	var def := MachineDef.new()
	def.id = id
	def.display_name = display_name
	def.color = color
	def.kind = MachineDef.Kind.STORAGE
	def.build_cost = 25
	def.storage_item = storage_item
	def.storage_capacity = capacity
	return def
