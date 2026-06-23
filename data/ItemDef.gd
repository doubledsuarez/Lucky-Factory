class_name ItemDef extends Resource
## A thing that rides a belt: material, ingot, or robot part.

enum Slot { NONE, LEGS, TORSO, HEAD, ARMS }
enum Shape { SQUARE, TRAPEZOID, TRIANGLE, DIAMOND, HEXAGON, CIRCLE }

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE       # stand-in color until we have art
@export var shape: Shape = Shape.SQUARE       # placeholder shape so items read apart at a glance
@export var stack_size: int = 1
@export var tier: int = 1
@export var slot: Slot = Slot.NONE           # only set on robot parts
@export var texture: Texture2D

# combat stats, only meaningful on robot parts (slot != NONE); read by the battle phase
@export var armor: int = 0
@export var speed: float = 0.0               # legs and torso
@export var turn_rate: float = 0.0           # torso
@export var damage: int = 0                  # arms
@export var attack_range: float = 0.0        # arms
@export var attack_speed: float = 0.0        # arms
