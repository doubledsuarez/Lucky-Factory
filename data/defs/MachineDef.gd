class_name MachineDef extends Resource
## A placeable machine: source, crafter, or storage.

enum Kind { SOURCE, CRAFTER, STORAGE }

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.GRAY
@export var kind: Kind = Kind.CRAFTER
@export var recipe: Recipe              # crafter
@export var source_item: StringName     # source
@export var storage_item: StringName    # storage
@export var storage_capacity: int = 0   # storage
