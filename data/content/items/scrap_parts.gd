extends RefCounted
## Scrap-tier robot parts: three archetypes (Boxer/Hunter/Warrior) per slot.

static func register(database) -> void:
	# heads carry armor only
	database.add_item(ItemBuilders.head(&"head_boxer", "Scrap Boxer Head", 20))
	database.add_item(ItemBuilders.head(&"head_hunter", "Scrap Hunter Head", 5))
	database.add_item(ItemBuilders.head(&"head_warrior", "Scrap Warrior Head", 10))
	# torsos: armor, turn rate, speed
	database.add_item(ItemBuilders.torso(&"torso_boxer", "Scrap Boxer Torso", 20, 0.75, 0.9))
	database.add_item(ItemBuilders.torso(&"torso_hunter", "Scrap Hunter Torso", 5, 1.25, 1.1))
	database.add_item(ItemBuilders.torso(&"torso_warrior", "Scrap Warrior Torso", 10, 1.0, 1.0))
	# legs: armor, speed
	database.add_item(ItemBuilders.legs(&"legs_boxer", "Scrap Boxer Legs", 10, 0.5))
	database.add_item(ItemBuilders.legs(&"legs_hunter", "Scrap Hunter Legs", 5, 2.0))
	database.add_item(ItemBuilders.legs(&"legs_warrior", "Scrap Warrior Legs", 5, 1.0))
	# arms: armor, damage, range, attack speed
	database.add_item(ItemBuilders.arms(&"arms_boxer", "Scrap Boxer Fists", 10, 10, 1.0, 2.0))
	database.add_item(ItemBuilders.arms(&"arms_warrior", "Scrap Warrior Spear", 10, 15, 3.0, 1.0))
	database.add_item(ItemBuilders.arms(&"arms_hunter", "Scrap Hunter Rifle", 5, 20, 10.0, 1.0))
