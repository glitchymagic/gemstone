class_name CorePC
extends RefCounted
## The original's Power Change machine (docs/PC.md, "Port" section; fx-pc). Tables only: the fighter runs them
## (fighter.gd "Power Change (fx-pc)"). Everything here is read off the disc running in Flycast:
## - game/assets/fidelity/pc_moves.json (tools/pc_table.py): per fighter, the transform / revert (state 23) and every
##   Drive / Fusion as the original's own per-frame rows [kind, mot, motion frame, fwd cm, side cm, up cm, PC flag],
##   the gauge cost row of each move and the state it leaves into.
## - the gauge: 2400 full, -1 per frame in round phase 3 only (0x0C093528), nothing refills it.
## - the triggers: transform the frame the third gem counts from the free / attack / lying states logged; revert when
##   the gauge is 0 and the fighter is not attacking (10 / 11) or already in state 23 (player tick 0x0C0934DC).

const GAUGE_FULL := 2400
const UNITS := 24.0                          # the remaster's gauge 0..100 (Rules.GAUGE_MAX) = the game's 0..2400 / 24
const TF_FROM := [0, 31, 32, 5, 6, 10, 15, 16]   # logged: every state a transform started from (115 transforms)
const NO_REVERT := [10, 11, 23]
const GROUND_FREE := [0, 2, 31, 32]          # where a Drive / Fusion press starts the move on the ground
const AIR_FREE := [5, 14]

static var _t := {}

static func _load() -> void:
	if _t.is_empty() and FileAccess.file_exists("res://assets/fidelity/pc_moves.json"):
		_t = JSON.parse_string(FileAccess.get_file_as_string("res://assets/fidelity/pc_moves.json"))

static func fighter(char_id: String) -> Dictionary:
	_load()
	return (_t.get("fighters", {}) as Dictionary).get(char_id, {})

## state 23 rows: what = "tf" (transform) | "rv" (revert); air picks the airborne version when it was logged
static func chain(char_id: String, what: String, air: bool) -> Array:
	var d: Dictionary = fighter(char_id).get(what, {})
	var c: Dictionary = d.get("air" if air and d.has("air") else "ground", d.get("air", {}))
	return c.get("rows", [])

## Drive / Fusion: name = X | Y (ground Drives), AX | AY (air Drives), FX | FY (Fusions A+X / A+Y)
static func move(char_id: String, name: String) -> Dictionary:
	return (fighter(char_id).get("moves", {}) as Dictionary).get(name, {})

static func has_move(char_id: String, name: String) -> bool:
	return not move(char_id, name).is_empty()

## the round is on (phase 3): the gauge only ticks then; outside a Fight (tests) always
static func fight_on(f: Node) -> bool:
	var p := f.get_parent()
	if p == null or not (p is Fight): return true
	return (p as Fight).phase == Fight.R.FIGHT

## the transform's morph row (the PC flag's first 1) and the revert's swap row (its first 0)
static func flag_row(rows: Array, want: int) -> int:
	for i in rows.size():
		if int((rows[i] as Array)[6]) == want: return i
	return -1
