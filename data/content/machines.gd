extends RefCounted
## Every machine in the game. Add new ones here.

static func register(database) -> void:
	database.add_machine(_source(&"depo", "Depo", Color(0.35, 0.28, 0.18), &"scrap"))
	database.add_machine(_crafter(&"forge", "Forge", Color(0.80, 0.45, 0.20), _scrap_to_ingot()))
	database.add_machine(_storage(&"bank", "Bank", Color(0.30, 0.45, 0.70), &"ingot", 100))

static func _scrap_to_ingot() -> Recipe:
	var recipe := Recipe.new()
	recipe.inputs = {&"scrap": 1}
	recipe.output_id = &"ingot"
	recipe.output_count = 1
	recipe.craft_time = 5.0
	return recipe

static func _source(id: StringName, display_name: String, color: Color, source_item: StringName) -> MachineDef:
	var def := MachineDef.new()
	def.id = id
	def.display_name = display_name
	def.color = color
	def.kind = MachineDef.Kind.SOURCE
	def.source_item = source_item
	return def

static func _crafter(id: StringName, display_name: String, color: Color, recipe: Recipe) -> MachineDef:
	var def := MachineDef.new()
	def.id = id
	def.display_name = display_name
	def.color = color
	def.kind = MachineDef.Kind.CRAFTER
	def.recipe = recipe
	return def

static func _storage(id: StringName, display_name: String, color: Color, storage_item: StringName, capacity: int) -> MachineDef:
	var def := MachineDef.new()
	def.id = id
	def.display_name = display_name
	def.color = color
	def.kind = MachineDef.Kind.STORAGE
	def.storage_item = storage_item
	def.storage_capacity = capacity
	return def
