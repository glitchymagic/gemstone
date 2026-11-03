extends SceneTree
const QuietExit = preload("res://tests/quiet_exit.gd")
## Fidelity pass: one fight driven by an input tape for BOTH fighters (tools/tapes.py), logged per frame in the original's
## reference-log schema (tools/reflog.py) so tools/fidelity_diff.py can compare it with the Flycast run of the same tape.
## Godot --headless --path game --fixed-fps 60 -s res://tests/tape_run.gd -- TAPE.txt OUT.jsonl STAGE p1,p2 [REF.jsonl]
## REF = the original's log of the same tape: its camera decides the D-pad -> world mapping (isolates movement from the
## camera, which has its own audit).
## Also writes OUT.objs.jsonl (fx-cov): per tape frame the arena's gems and props (cm, feet frame), the remaster side of
## the original's object log (tools/covlog.py), for gem drop / pick-up / respawn and item diffs.
var f: Fight
var obj_log: FileAccess
var n := 0
var done := false
## fx-item2: the disc's C rand state per row (o_TAPE.jsonl "rand"). Its other draws (effects, sparks) are not ported, so
## a rand-picked thing (the chests' items, 0x0C0CC72E) only matches when each frame starts from the disc's state
var disc_rand: Array = []
var disc_first_item := -1   # the disc's chest 1 item (o_TAPE.obj.jsonl): drawn before the harness's rand reset
var reach: Node   # fx-reach (PS_REACH=1): OUT.reach.jsonl, per tape frame each fighter's joints as the hit test poses them

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	f = Fight.new(); f.cpu_flags = [false, false]; f.test_mode = true
	f.stage = str(a[2]); f.chars = Array(str(a[3]).split(","))
	for ln in FileAccess.get_file_as_string(str(a[0])).split("\n"):
		var parts := ln.strip_edges().split(";")
		var w := parts[0].strip_edges().split(" ", false)
		if w.size() >= 2:
			var cmds := []
			for k in range(1, parts.size()): cmds.append(parts[k].strip_edges())
			f.tape.append([w[0].hex_to_int(), w[1].hex_to_int(), cmds])
	if a.size() > 4 and FileAccess.file_exists(str(a[4])):
		for ln in FileAccess.get_file_as_string(str(a[4])).split("\n"):
			if ln.strip_edges() == "": continue
			var r = JSON.parse_string(ln)
			f.tape_cam.append([r.eye[0] * 0.01, r.eye[1] * 0.01, r.eye[2] * 0.01, r.tgt[0] * 0.01, r.tgt[1] * 0.01, r.tgt[2] * 0.01])
			disc_rand.append(int(r.get("rand", -1)))
	if a.size() > 4:
		var op := str(a[4]).trim_suffix(".jsonl") + ".obj.jsonl"
		if FileAccess.file_exists(op):
			var fo := FileAccess.open(op, FileAccess.READ)
			var r0 = JSON.parse_string(fo.get_line()) if fo else null
			if r0 is Array:
				for o in r0:
					if int(o[1]) == 2 and int(o[3]) == 7: disc_first_item = int(o[8])
			Items.tape_first_item = disc_first_item
	f.tape_log = FileAccess.open(str(a[1]), FileAccess.WRITE)
	obj_log = FileAccess.open(str(a[1]).trim_suffix(".jsonl") + ".objs.jsonl", FileAccess.WRITE)
	f.tape_done.connect(func(): done = true)
	root.add_child(f)
	if OS.get_environment("PS_REACH") != "":
		reach = ReachLog.new()
		reach.fight = f
		reach.out = FileAccess.open(str(a[1]).trim_suffix(".jsonl") + ".reach.jsonl", FileAccess.WRITE)
		reach.process_physics_priority = 100000   # after Fight's physics: the pose the frame's hit tests used
		root.add_child(reach)

## MainLoop's physics step runs before the nodes' (Fight logs its row there, before the frame's input): same frame state
func _physics_process(_d: float) -> bool:
	if f and f.tape_f >= 0 and f.tape_f < disc_rand.size() and int(disc_rand[f.tape_f]) >= 0:
		CPUGame.rand_state = int(disc_rand[f.tape_f])
	if obj_log and f and f.tape_f >= 0 and f.arena:
		var gs := []
		for g in f.arena.gems:
			var p: Vector3 = g.global_position * 100.0
			gs.append([snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)])
		var ps := []
		for k in f.arena.props.size():
			var q = f.arena.props[k]
			if q is Node3D:
				var p: Vector3 = q.global_position * 100.0
				ps.append([k, snappedf(p.x, 0.1), snappedf(p.y, 0.1), snappedf(p.z, 0.1)])
		var row := {"f": f.tape_f, "gems": gs, "props": ps}
		if f.arena.get("items") != null: row["items"] = f.arena.items.log_rows()   # fx-item2: chests (7) / items (6)
		obj_log.store_line(JSON.stringify(row))
	return false

func _process(_d: float) -> bool:
	n += 1
	if done or n > 60 * 600:
		if f.tape_log: f.tape_log.close()
		if obj_log: obj_log.close()
		if reach: reach.out.close()
		print("TAPE_END frame %d" % n)
		QuietExit.drain(root)   # BUG-38: stop the sounds + let the audio thread free their playbacks (--fixed-fps outruns it)
		quit()
		return true
	return false

## fx-reach: joints b00-b18 world (cm) + feet / facing / the core motion and frame of each fighter, after the frame's ticks
class ReachLog extends Node:
	var fight: Fight
	var out: FileAccess
	func _physics_process(_d: float) -> void:
		if out == null or fight == null or fight.tape_f < 0: return
		var ps := []
		for fi in fight.fighters:
			var fr: Fighter = fi
			var m := fr.model as PSModel
			var js := []
			if m:
				var sk := m.skeleton()
				for j in 19:
					var bi := sk.find_bone("b%02d" % j) if sk else -1
					if bi < 0: js.append([]); continue
					var t: Transform3D = sk.global_transform * sk.get_bone_global_pose(bi)
					js.append([snappedf(t.origin.x * 100.0, 0.01), snappedf(t.origin.y * 100.0, 0.01), snappedf(t.origin.z * 100.0, 0.01),
						snappedf(t.basis.get_scale().x * 100.0, 0.001)])
			var p := fr.global_position * 100.0
			var mo := fr._motion()
			ps.append({"x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.01),
				"ang": int(posmod(roundi(atan2(fr.facing.x, fr.facing.z) / TAU * 65536.0), 65536)),
				"gmo": fr.gmo if fr.core_atk else "", "gmo_f": fr.gmo_f, "mk": mo[0], "mf": mo[1], "gst": fr.gst,
				"pin": [snappedf(m.pin.x * 100.0, 0.01), snappedf(m.pin.z * 100.0, 0.01)] if m else [], "j": js})
		out.store_line(JSON.stringify({"f": fight.tape_f, "p": ps}))
