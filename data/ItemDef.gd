class_name ItemDef extends Resource
## A thing that rides a belt: material, ingot, or robot part.

enum Slot { NONE, LEGS, TORSO, HEAD, ARMS }

@export var id: StringName
@export var display_name: String
@export var color: Color = Color.WHITE       # stand-in color until we have art
@export var stack_size: int = 1
@export var tier: int = 1
@export var slot: Slot = Slot.NONE           # only set on robot parts
@export var texture: Texture2D
