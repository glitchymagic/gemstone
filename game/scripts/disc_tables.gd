class_name DiscTables
extends RefCounted
## Tables the game's code reads straight out of the original program (damage scales, the CPU's strength by level,
## the select-screen slots, item picks...). They are not in this repository: the importer reads them from your own
## 1ST_READ.BIN into res://assets/disc/tables.json (importer/tables.py lists every address).

const PATH := "res://assets/disc/tables.json"
static var _t := {}
static var _loaded := false

static func _load() -> void:
	_loaded = true
	if not FileAccess.file_exists(PATH):
		push_error("DiscTables: %s is missing: run the importer on your Power Stone disc first" % PATH)
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not d is Dictionary: return
	_t = d.get("tables", {})
	for k in d.get("ints", []):   # JSON numbers parse as float; byte / word tables go back to int
		if _t.has(k): _t[k] = _ints(_t[k])

static func _ints(v):
	if v is Array: return v.map(func(x): return _ints(x))
	return int(v)

static func list(name: String) -> Array:
	if not _loaded: _load()
	if not _t.has(name):
		push_error("DiscTables: no table '%s' (re-run the importer)" % name)
		return []
	return _t[name]

static func ready() -> bool:
	if not _loaded: _load()
	return not _t.is_empty()
