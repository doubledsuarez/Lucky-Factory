extends RefCounted
## The tech tree, mirroring docs/Tech Tree Worksheet.csv. Node ids match item/machine/tool ids.
## Only real nodes live here -- plumbing (robot, depo) is left out. Portals are nodes (they gate active state).

static func register(database) -> void:
	# materials
	database.add_tech_node(_n(&"scrap", &"material", "Scrap", [], true))
	database.add_tech_node(_n(&"scrap_ingot", &"material", "Scrap Ingot", [&"t1_forge"], true))
	# tools
	database.add_tech_node(_n(&"t1_belt", &"tool", "T1 Belt", [], true))
	database.add_tech_node(_n(&"splitter", &"tool", "Splitter", [], false))
	database.add_tech_node(_n(&"merger", &"tool", "Merger", [], false))
	# machines
	database.add_tech_node(_n(&"t1_forge", &"machine", "T1 Forge", [&"scrap"], true))
	database.add_tech_node(_n(&"t1_crafter", &"machine", "T1 Crafter", [&"scrap_ingot"], true))
	database.add_tech_node(_n(&"t1_assembler", &"machine", "T1 Assembler", [&"t1_crafter"], true))
	database.add_tech_node(_n(&"storage", &"machine", "Storage", [&"scrap_ingot"], true))
	# portals (blue starts active; the other four unlock via cards -- parents get slotted in later)
	database.add_tech_node(_n(&"portal_blue", &"portal", "Blue Portal", [], true))
	database.add_tech_node(_n(&"portal_green", &"portal", "Green Portal", [], false))
	database.add_tech_node(_n(&"portal_red", &"portal", "Red Portal", [], false))
	database.add_tech_node(_n(&"portal_orange", &"portal", "Orange Portal", [], false))
	database.add_tech_node(_n(&"portal_yellow", &"portal", "Yellow Portal", [], false))
	# heads (each archetype branches off the assembler)
	database.add_tech_node(_n(&"scrap_boxer_head", &"part", "Scrap Boxer Head", [&"t1_assembler"], true))
	database.add_tech_node(_n(&"scrap_warrior_head", &"part", "Scrap Warrior Head", [&"t1_assembler"], false))
	database.add_tech_node(_n(&"scrap_hunter_head", &"part", "Scrap Hunter Head", [&"t1_assembler"], false))
	# boxer chain
	database.add_tech_node(_n(&"scrap_boxer_torso", &"part", "Scrap Boxer Torso", [&"scrap_boxer_head"], true))
	database.add_tech_node(_n(&"scrap_boxer_legs", &"part", "Scrap Boxer Legs", [&"scrap_boxer_head"], true))
	database.add_tech_node(_n(&"scrap_boxer_fists", &"part", "Scrap Boxer Fists", [&"scrap_boxer_head"], true))
	# warrior chain
	database.add_tech_node(_n(&"scrap_warrior_torso", &"part", "Scrap Warrior Torso", [&"scrap_warrior_head"], false))
	database.add_tech_node(_n(&"scrap_warrior_legs", &"part", "Scrap Warrior Legs", [&"scrap_warrior_head"], false))
	database.add_tech_node(_n(&"scrap_warrior_spear", &"part", "Scrap Warrior Spear", [&"scrap_warrior_head"], false))
	# hunter chain
	database.add_tech_node(_n(&"scrap_hunter_torso", &"part", "Scrap Hunter Torso", [&"scrap_hunter_head"], false))
	database.add_tech_node(_n(&"scrap_hunter_legs", &"part", "Scrap Hunter Legs", [&"scrap_hunter_head"], false))
	database.add_tech_node(_n(&"scrap_hunter_rifle", &"part", "Scrap Hunter Rifle", [&"scrap_hunter_head"], false))
	# buffs (one chain per archetype head; they stack toward more scrap and time)
	database.add_tech_node(_n(&"1000_scrap_0", &"buff", "1000 Scrap", [&"scrap_boxer_head"], false))
	database.add_tech_node(_n(&"1000_scrap_1", &"buff", "1000 Scrap", [&"scrap_warrior_head"], false))
	database.add_tech_node(_n(&"1000_scrap_2", &"buff", "1000 Scrap", [&"scrap_hunter_head"], false))
	database.add_tech_node(_n(&"extra_time_0", &"buff", "Extra Time", [&"1000_scrap_0"], false))
	database.add_tech_node(_n(&"extra_time_1", &"buff", "Extra Time", [&"1000_scrap_1"], false))
	database.add_tech_node(_n(&"extra_time_2", &"buff", "Extra Time", [&"1000_scrap_2"], false))

static func _n(id: StringName, category: StringName, display_name: String, parents: Array, starts_unlocked: bool) -> TechNode:
	var node := TechNode.new()
	node.id = id
	node.category = category
	node.display_name = display_name
	node.parents = parents
	node.starts_unlocked = starts_unlocked
	return node
