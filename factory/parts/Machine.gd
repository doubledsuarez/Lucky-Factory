class_name Machine extends RefCounted
## A placed machine instance: its definition plus the live state of what it's holding and making.

var definition: MachineDef
var origin: Vector2i           # top-left cell of the footprint
var orientation: int = 0       # 0-3 quarter turns
var footprint := Vector2i.ONE  # rotated size in cells
var world_ports: Array = []    # { coord, side, role } in world space
var recipe: Recipe = null      # what this crafter is set to make
var progress: float = 0.0
var inputs: Dictionary = {}    # crafter: item id -> count; assembler: slot -> ItemDef
var output_item: ItemDef = null
var output_count: int = 0      # finished items waiting to leave
var output_loadout: RobotLoadout = null  # assembler: the robot waiting to leave
var stored: int = 0            # source reservoir (the depo)
