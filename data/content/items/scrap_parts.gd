extends RefCounted
## Scrap-tier robot parts: three archetypes (Boxer/Hunter/Warrior) per slot.
## Tuned so the three pure builds land at roughly equal power -- boxer tanks, warrior hits hardest
## per swing, hunter is fast and long-ranged. Mixing parts trades these off.

static func register(database) -> void:
	# heads carry armor only
	database.add_item(ItemBuilders.head(&"scrap_boxer_head", "Scrap Boxer Head", 30))
	database.add_item(ItemBuilders.head(&"scrap_hunter_head", "Scrap Hunter Head", 6))
	database.add_item(ItemBuilders.head(&"scrap_warrior_head", "Scrap Warrior Head", 12))
	# torsos: armor, turn rate, speed
	# the boxer's shield soaks ranged fire -- it's how brawlers walk through rifles to reach the line
	# (12 vs a scrap rifle's 13 leaves chip damage of 1; tougher energy weapons will punch through)
	database.add_item(ItemBuilders.torso(&"scrap_boxer_torso", "Scrap Boxer Torso", 28, 0.75, 0.9, 12))
	database.add_item(ItemBuilders.torso(&"scrap_hunter_torso", "Scrap Hunter Torso", 6, 1.25, 1.1))
	database.add_item(ItemBuilders.torso(&"scrap_warrior_torso", "Scrap Warrior Torso", 12, 1.0, 1.0))
	# legs: armor, speed
	database.add_item(ItemBuilders.legs(&"scrap_boxer_legs", "Scrap Boxer Legs", 18, 0.5))
	database.add_item(ItemBuilders.legs(&"scrap_hunter_legs", "Scrap Hunter Legs", 4, 2.0))
	database.add_item(ItemBuilders.legs(&"scrap_warrior_legs", "Scrap Warrior Legs", 6, 1.0))
	# arms: armor, damage, range, attack speed
	database.add_item(ItemBuilders.arms(&"scrap_boxer_fists", "Scrap Boxer Fists", 12, 12, 1.0, 1.2))
	database.add_item(ItemBuilders.arms(&"scrap_warrior_spear", "Scrap Warrior Spear", 5, 50, 3.0, 1.0))
	database.add_item(ItemBuilders.arms(&"scrap_hunter_rifle", "Scrap Hunter Rifle", 4, 13, 10.0, 2.0))
