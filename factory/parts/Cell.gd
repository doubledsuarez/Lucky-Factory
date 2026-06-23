class_name Cell extends RefCounted
## One grid square. It's either a belt, part of a machine, or a router (splitter/merger).

var kind: int
var input_direction: int = 2   # belt/router: side items come in from
var output_direction: int = 0  # belt/router: side items go out
var item: Item = null          # belt or router: one item at a time
var machine: Machine = null    # set on every cell a machine covers
var machine_origin := Vector2i.ZERO  # which machine cell is the origin
var router_kind: int = 0       # splitter or merger, on router cells
var round_robin_index: int = 0 # splitter: next output side to try
var stall_time: float = 0.0    # splitter: how long the current output has been busy
