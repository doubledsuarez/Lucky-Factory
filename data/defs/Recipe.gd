class_name Recipe extends Resource
## What a machine eats and what it makes.

@export var inputs: Dictionary = {}    # item id -> count
@export var output_id: StringName
@export var output_count: int = 1
@export var craft_time: float = 1.0
