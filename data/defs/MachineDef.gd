class_name MachineDef extends Resource
## A placeable machine: source, crafter, or storage.

enum Kind { SOURCE, CRAFTER, STORAGE, ASSEMBLER, PORTAL }

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.GRAY
@export var kind: Kind = Kind.CRAFTER
@export var build_cost: int = 0         # ingots to place it
@export var footprint: Vector2i = Vector2i.ONE
@export var ports: Array = []           # MachinePort, in the default orientation
@export var recipe: Recipe              # crafter (default / single recipe)
@export var recipes: Array = []         # crafter with a recipe you pick when placing (which part)
@export var source_item: StringName     # source
@export var storage_item: StringName    # storage
@export var storage_capacity: int = 0   # storage
@export var portal_color: StringName    # portal: which manifest it feeds (blue/green/red/orange/yellow)
