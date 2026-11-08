class_name Combat
extends RefCounted
## STUB (interface only) - core logic is being implemented.

const Z_HEAD := 0
const Z_CHEST := 1
const Z_STOMACH := 2
const Z_LEGS := 3


## Line of sight test against world geometry (ignores soldiers).
static func can_see(from: Vector3, to: Vector3) -> bool:
	return true
