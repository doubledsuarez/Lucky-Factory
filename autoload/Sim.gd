extends Node
## Global speed multiplier. 1.0 is normal, 0.5 slows the factory down, 2.0 speeds it up.

signal speed_changed(speed: float)

var speed: float = 1.0:
	set(value):
		speed = value
		speed_changed.emit(value)
