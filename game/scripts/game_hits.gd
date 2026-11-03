class_name GameHits
extends RefCounted
## The game's own hit data, read from the owner's disc by tools/hitdata.py export (assets/ripped/pN0_hit.json):
##  - per motion the hit steps: [first frame, frames, hit id, attack sphere set, body sphere set] (Pn0_HIT.BIN);
##    a hit id stays armed until a later step changes it, the steps' end clears everything
##  - per hit id the attack record: base damage (health is 240) and its class / type bytes (1ST_READ 0x0C338A98)
##  - sphere sets: [joint, sphere] pairs; spheres are [x, y, z, r] in cm in the joint's frame, joint 255 = the
##    fighter's root (the PL block in 1ST_READ: attack sets +0, body sets +0x640, spheres +0x1900)
## The game tests the attacker's 4 attack spheres (player +0x148) against the victim's 12 body spheres (+0x188).

const DIR := "res://assets/ripped/"
const ROOT_JOINT := 255
static var _cache := {}

var ok := false
var defence := 1.0
var combo := []          # damage scale by hits in a row (0x0C32E0A4)
var spheres := {}        # "entry" -> [x, y, z, r]
var atk_sets := {}       # "set" -> [[joint, entry], ...]
var body_sets := {}
var moves := {}          # "k1_016" -> [[f0, frames, hit, aset, bset], ...]
var hits := {}           # "hid" -> {dmg, class, type, level, react}
var body_default := {}   # "k0_000" -> body set seen in logged fights for motions without hit steps
var code_hits := {}      # "k1_100" -> hit id the game's code arms itself during that motion (logged)
var proj_base := {}      # "k1_101" -> base damage of the projectile that move throws (formula inverted on logged hits)

static func load_for(file_id: String) -> GameHits:
	if _cache.has(file_id): return _cache[file_id]
	var g := GameHits.new()
	var p := DIR + file_id + "_hit.json"
	if FileAccess.file_exists(p):
		var j = JSON.parse_string(FileAccess.get_file_as_string(p))
		if j is Dictionary:
			g.ok = true
			g.defence = float(j.get("defence", 1.0))
			g.combo = j.get("combo", [])
			g.spheres = j.get("spheres", {})
			g.atk_sets = j.get("atk_sets", {})
			g.body_sets = j.get("body_sets", {})
			g.moves = j.get("moves", {})
			g.hits = j.get("hits", {})
			g.body_default = j.get("body_default", {})
			g.code_hits = j.get("code_hits", {})
			g.proj_base = j.get("proj_base", {})
	_cache[file_id] = g
	return g

## "f0k1_016" -> "k1_016" (clip names carry a 2-letter fighter prefix)
static func key_of(clip: String) -> String:
	# "f0k1_016" -> "k1_016". The key is the clip's last 6 characters (kN_NNN): Kraken's own prefix "k0" / "k1" starts
	# with a k too, so the first "k" gave "k0k1_016" and none of his motions found their hit steps (no hits, no ids)
	var n := clip.length()
	if n >= 6 and clip[n - 6] == "k" and clip[n - 4] == "_": return clip.substr(n - 6)
	var i := clip.find("k")
	return clip.substr(i) if i >= 0 else clip

static var REARM_STEPS := not OS.has_environment("PS_NO_STEP_REARM")   # A/B switch for the ledger

func has_move(key: String) -> bool:
	return moves.has(key)

## The game's state at motion frame f: {hit, arm, aset, bset}. The hit id persists across steps until a step sets a
## new one (arm = the frame it was set: the game clears its list of fighters already hit there, 0x0C09B008). Every later
## step clears that list again, one frame late (the step is read after the frame's hit test): Jack's Drive X k1/96
## (steps every 3 frames from 13) hits on the disc at 13, 17, 20 .. 41, his air Drive X k1/102 at 13, 15, 18 .. 27 (w8)
func at(key: String, f: int) -> Dictionary:
	var st: Array = moves.get(key, [])
	var hid := 0; var arm := -1
	for s in st:
		if int(s[2]) != 0: hid = int(s[2]); arm = int(s[0])
		elif hid != 0 and REARM_STEPS: arm = int(s[0]) + 1
		if f >= int(s[0]) and f < int(s[0]) + int(s[1]):
			if hid == 0 and code_hits.has(key):   # armed by the game's code (logged), re-armed every 5 frames there
				hid = int(code_hits[key]); arm = f - f % 5
			return {"hit": hid, "arm": arm, "aset": int(s[3]), "bset": int(s[4]), "held": int(s[1]) >= 255}
	return {"hit": 0, "arm": -1, "aset": 0, "bset": int(body_default.get(key, _default_body(key))), "held": false}

## Motions never seen in a logged fight: by kind (standing k0 = coarse set 10, k4 throws = 12, the rest the full set)
static func _default_body(key: String) -> int:
	if key.begins_with("k0"): return 10
	if key.begins_with("k4"): return 12
	return 0

## The first hit id a motion's steps arm (projectile moves: the steps arm it, the projectile carries it)
func first_hit(key: String) -> int:
	for s in moves.get(key, []):
		if int(s[2]) != 0: return int(s[2])
	return 0

## First and last motion frame with live attack spheres (for timing checks and the CPU)
func active_window(key: String) -> Vector2i:
	var st: Array = moves.get(key, [])
	var a := -1; var b := -1; var hid := 0
	for s in st:
		if int(s[2]) != 0: hid = int(s[2])
		if hid == 0 and code_hits.has(key): hid = int(code_hits[key])
		if hid != 0 and int(s[3]) != 0 and atk_sets.has(str(int(s[3]))):
			if a < 0: a = int(s[0])
			b = int(s[0]) + mini(int(s[1]), 120) - 1
	return Vector2i(a, b)

func record(hid: int) -> Dictionary:
	return hits.get(str(hid), {})

## World-space spheres [[center, radius_m], ...] of a set on a posed skeleton. Bone k = the game's part k ("bKK").
## from = first entry used: body sets start at 1 (entry 0 is the push sphere; the body-push test 0x0C0209C6 uses only it)
func world_spheres(sets: Dictionary, set_id: int, sk: Skeleton3D, root: Node3D, from := 0) -> Array:
	var out := []
	if set_id < 0 or sk == null: return out
	var s: Array = sets.get(str(set_id), [])
	var sx := sk.global_transform.basis.get_scale().x
	for ei in range(from, s.size()):
		var e: Array = s[ei]
		var sp: Array = spheres.get(str(int(e[1])), [0, 0, 0, 0])
		var r := float(sp[3])
		if r <= 0.0: continue
		var off := Vector3(float(sp[0]), float(sp[1]), float(sp[2]))
		var j := int(e[0])
		var c: Vector3
		var rs := sx
		if j == ROOT_JOINT:
			c = root.global_transform * (off * 0.01)
		else:
			var bi := sk.find_bone("b%02d" % j)
			if bi < 0: continue
			var bt := sk.get_bone_global_pose(bi)
			c = sk.global_transform * (bt * off)
			rs = sx * bt.basis.get_scale().x   # the joint's scale (fx-reach: the disc's radius = file radius x it)
		out.append([c, r * rs])
	return out

static func overlap(a: Array, b: Array) -> bool:
	for x in a:
		for y in b:
			var rr: float = float(x[1]) + float(y[1])
			if (x[0] as Vector3).distance_squared_to(y[0]) <= rr * rr: return true
	return false
