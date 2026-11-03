extends SceneTree
## BUG-41 world-query replay (fx-cpu3, docs/CPU.md "BUG-41 replay"): the disc's CPU logs (dumps/fidelity/cpu/cpu_*.jsonl,
## tools/cpu_stats.py) are fed through cpu_game.gd's WORLD hooks on a real Arena of the log's stage (P2's home stage):
## every logged frame puts the fighter where the disc had it (x/y/z cm, facing u16) and asks the port's predicates
##   0x400 (a) _w_ai_object_overhead   (disc Mode 0x00 = 10.0 JUMP 6)
##   0x40      the stuck counter (hdist to last frame < 5 cm in state 2 / 31, > 60 frames)   (disc Mode 0x60)
##   0x1000    _w_ai_zone != 0 (side-filtered like _think)                                   (disc Mode 0x80)
##   0x02      _w_ai_item_held                                                                (disc Mode 0x30)
## and compares with what the disc selected. A predicate that is true on a frame where the disc could have taken that
## interrupt (Mask has the bit, IntLv below it, own state allowed) but selected nothing / something lower = a false
## positive of the port's world query; a disc selection of that Mode with the predicate false = a miss. The places are
## binned on a 100 cm grid. Stage objects stay at their home spots (the logs carry no object lists).
##   Godot --headless --path game -s res://tests/cpu_world_replay.gd   PS_CPU_REPLAY=log.jsonl [PS_STAGE=stg10]

class Stub extends RefCounted:
	var global_position := Vector3.ZERO
	var facing := Vector3.BACK
	var carry = null
	var cpu_level := 9
	var char_id := "falcon"
	var opponent = null
	var powered := false
	var ai_st := 0

const NAMES := ["falcon", "ryoma", "wangtang", "jack", "gunrock", "galuda", "ayame", "rouge", "kraken", "valgas", "finalvalgas"]
const BITS := {"0x400a": 0x400, "0x40": 0x40, "0x1000": 0x1000, "0x02": 0x02}
const MODE := {"0x400a": 0x00, "0x40": 0x60, "0x1000": 0x80, "0x02": 0x30}

const SWEEP := [0.0, 0.3, 0.45, 0.6, 0.8, -0.3, -0.45, -0.6]   # negative = a ring of 8 points at that radius (any direction)
## cpu_game.gd _w_ai_object_overhead with the contact length d (metres) as a parameter
func _overhead_at(arena, me, d: float) -> bool:
	if d < 0.0:
		for k in 8:
			var a := TAU * k / 8.0
			if _overhead_pt(arena, me.global_position + Vector3(sin(a), 0, cos(a)) * -d, me.global_position.y): return true
		return false
	return _overhead_pt(arena, me.global_position + Vector3(me.facing.x, 0, me.facing.z).normalized() * d, me.global_position.y)

func _overhead_pt(arena, q: Vector3, y: float) -> bool:
	var ls: Array = arena.floor_levels(q.x, q.z)
	if ls.is_empty(): return false
	var up := false
	for l in ls:
		if absf(float(l) - y) <= 0.6: return false
		if float(l) >= y + 0.6 and float(l) <= y + 4.4: up = true
	return up

func _overhead_old(arena, me, d: float) -> bool:
	var q: Vector3 = me.global_position + Vector3(me.facing.x, 0, me.facing.z).normalized() * d
	var ls: Array = arena.floor_levels(q.x, q.z)
	if ls.is_empty(): return false
	var y: float = me.global_position.y
	var up := false
	for l in ls:
		if absf(float(l) - y) <= 0.6: return false
		if float(l) >= y + 0.6 and float(l) <= y + 4.4: up = true
	return up

func _cell(r: Dictionary) -> String:
	return "%d,%d" % [int(floor(float(r.x) / 100.0)) * 100, int(floor(float(r.z) / 100.0)) * 100]

func _initialize() -> void:
	CPUGame.load_data()
	var path := OS.get_environment("PS_CPU_REPLAY")
	var rows: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() != "": rows.append(JSON.parse_string(line))
	if rows.is_empty(): print("FAIL no rows in ", path); quit(1); return
	var stage := OS.get_environment("PS_STAGE") if OS.has_environment("PS_STAGE") else "stg%d0" % int(rows[0].p[1].ch)
	if stage == "stg100": stage = "stga0"
	var arena := Arena.new(); arena.stage = stage
	root.add_child(arena)
	arena.build(1)
	var st := [Stub.new(), Stub.new()]
	st[0].opponent = st[1]; st[1].opponent = st[0]
	var cs := []
	for i in 2:
		st[i].char_id = NAMES[mini(int(rows[0].p[i].ch), 10)]
		cs.append(CPUGame.new(st[i], arena, int(rows[0].lvl)))
	# per side, per check: frames true while open, false positives (open, true, disc did not take it), misses
	var res := [{}, {}]
	var stuck := [0, 0]; var last := [Vector3.ZERO, Vector3.ZERO]
	var disc_mode_frames := [{}, {}]; var nframes := [0, 0]
	var sweep := [{}, {}]
	for i in 2:
		for k in BITS: res[i][k] = {"true": 0, "open": 0, "fp": 0, "sel": 0, "miss": 0, "fp_at": {}, "miss_at": {}}
	for f in range(1, rows.size()):
		var pr: Dictionary = rows[f - 1]; var r: Dictionary = rows[f]
		if int(r.phase) != 3 or int(r.mvok) == 0: continue
		for i in 2:
			var a := float(int(pr.p[i].ang)) / 65536.0 * TAU
			st[i].global_position = Vector3(float(pr.p[i].x), float(pr.p[i].y), float(pr.p[i].z)) * 0.01
			st[i].facing = Vector3(sin(a), 0, cos(a))
			st[i].ai_st = int(pr.p[i].st)
		for i in 2:
			var p0: Dictionary = pr.p[i]; var p1: Dictionary = r.p[i]
			if int(p0.ch) == 10: continue
			var c: CPUGame = cs[i]
			var sti := int(p0.st)
			nframes[i] += 1
			var mk := "%02x" % int(p1.mode)
			disc_mode_frames[i][mk] = int(disc_mode_frames[i].get(mk, 0)) + 1
			var pos := Vector3(float(p0.x), 0, float(p0.z))
			if CPUGame.hdist(last[i], pos) < 5 and sti in [2, 31]: stuck[i] += 1
			else: stuck[i] = 0
			last[i] = pos
			var op := Vector3(float(pr.p[1 - i].x), 0, float(pr.p[1 - i].z))
			var pred := {}
			pred["0x400a"] = sti in [0, 2, 31, 5] and bool(c._w_ai_object_overhead())
			var took400: bool = int(p1.mode) == 0 and int(p1.intlv) == 0x400 and int(p0.intlv) != 0x400
			var open400: bool = (int(p0.mask) & 0x400) != 0 and int(p0.intlv) < 0x400
			for d in SWEEP:   # the same raster test at other contact lengths (metres): [fp, miss]
				var hit: bool = sti in [0, 2, 31, 5] and _overhead_at(arena, st[i], d)
				var sw: Array = sweep[i].get(str(d), [0, 0])
				if open400 and hit and not took400: sw[0] += 1
				if took400 and not hit: sw[1] += 1
				sweep[i][str(d)] = sw
			pred["0x40"] = stuck[i] > 60 and sti in [2, 31]
			var z := int(c._w_ai_zone())
			if z in [2, 3]: z = 0
			elif z == 4 and pos.z < op.z: z = 0
			elif z == 6 and op.z < pos.z: z = 0
			elif z == 5 and pos.x < op.x: z = 0
			elif z == 7 and op.x < pos.x: z = 0
			pred["0x1000"] = z != 0
			pred["0x02"] = c._w_ai_item_held() != null
			var selected: bool = int(p1.mode) != int(p0.mode) or int(p1.tbl) != int(p0.tbl) or int(p1.intlv) != int(p0.intlv)
			for k in BITS:
				var b: int = BITS[k]
				var e: Dictionary = res[i][k]
				var open: bool = (int(p0.mask) & b) != 0 and int(p0.intlv) < b
				var took: bool = int(p1.mode) == int(MODE[k]) and int(p1.intlv) == b
				if pred[k]: e["true"] += 1
				if open:
					e["open"] += 1
					if pred[k] and not took:
						e["fp"] += 1
						var cl := _cell(p0) + " st%d" % sti
						e["fp_at"][cl] = int(e["fp_at"].get(cl, 0)) + 1
				if k == "0x40" and took and int(p0.intlv) != 0x40: stuck[i] = 0   # the disc's counter resets when 0x40 fires
				if took and selected:
					e["sel"] += 1
					if not pred[k]:
						e["miss"] += 1
						var cl2 := _cell(p0) + " st%d" % sti
						e["miss_at"][cl2] = int(e["miss_at"].get(cl2, 0)) + 1
	print("log ", path.get_file(), " stage ", stage, " area ", arena.has_area())
	for i in 2:
		if nframes[i] == 0: continue
		var parts := []
		for k in BITS:
			var e: Dictionary = res[i][k]
			parts.append("%s true %.3f fp %d miss %d/%d" % [k, float(e["true"]) / nframes[i], e["fp"], e["miss"], e["sel"]])
		print("P%d %s %d frames | %s" % [i + 1, st[i].char_id, nframes[i], " | ".join(parts)])
		for k in BITS:
			var e: Dictionary = res[i][k]
			for which in ["fp_at", "miss_at"]:
				var d: Dictionary = e[which]
				if d.is_empty(): continue
				var ks := d.keys(); ks.sort_custom(func(x, y): return d[x] > d[y])
				var top := []
				for q in ks.slice(0, 6): top.append("(%s) %d" % [q, d[q]])
				print("   %s %s: %s" % [k, which, ", ".join(top)])
		var ms := []
		for m in disc_mode_frames[i]: ms.append("%s %.3f" % [m, float(disc_mode_frames[i][m]) / nframes[i]])
		print("   disc Mode shares: ", ", ".join(ms))
		print("   0x400a contact sweep [fp, miss]: ", sweep[i])
	print("JSON ", JSON.stringify({"log": path.get_file(), "stage": stage, "res": res, "n": nframes}))
	quit(0)
