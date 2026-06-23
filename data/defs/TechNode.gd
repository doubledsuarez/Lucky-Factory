class_name TechNode extends RefCounted
## One node in the tech tree. Its id matches the item/machine/tool id it unlocks (buffs own their id).

var id: StringName
var category: StringName        # material / tool / machine / part / buff -- drives node color
var display_name: String
var parents: Array = []          # prerequisite node ids; empty = a root (leftmost)
var starts_unlocked: bool = false
# derived when the graph is built
var column: int = 0              # left-to-right depth (longest path from a root)
var children: Array = []         # node ids that list this one as a parent
