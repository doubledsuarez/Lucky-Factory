class_name MachinePort extends Resource
## One connection point on a machine: which footprint cell it's on, which edge it faces, and whether
## items come in or go out there. Authored in the machine's default orientation; rotated when placed.

enum Role { INPUT, OUTPUT }

@export var cell: Vector2i = Vector2i.ZERO   # offset within the footprint
@export var side: int = 0                    # edge it faces (0 right, 1 down, 2 left, 3 up)
@export var role: Role = Role.INPUT
