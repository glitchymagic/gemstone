extends SceneTree
## Same-start frame diff of the AI alone (docs/CPU.md section 12): the ported CPU (scripts/cpu_game.gd) is fed the
## ORIGINAL's logged world every frame (a CPU-vs-CPU log of the disc, tools/cpu_stats.py: both fighters' x/y/z,
## velocity, facing, state, health, Power Change, hit id, MV_OK, level, and the C rand state), runs P1's AI then P2's
## as 0x0C092B8C does, and its Mode / IntLv / Table / button bits are compared with the log's next frame.
## Isolates the AI's decisions from the fighter core and the camera (directions are not compared: the log has no
## camera yaw). Stage objects: none (the log has no object lists) -> frames whose original choice needed one diverge.
##   Godot --headless --path game -s res://tests/cpu_replay.gd   PS_CPU_REPLAY=log.jsonl PS_FIGHT=0 [PS_REPLAY_N=frames]

class Stub extends RefCounted:
	var global_position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var vcm := Vector3.ZERO
	var facing := Vector3.BACK
	var ai_st := 0
	var ai_hid := 0
	var powered := false
	var hp := 240
	var gems := 0
	var carry = null
	var cpu_level := 9
	var char_id := "falcon"
	var opponent = null

const NAMES := ["falcon", "ryoma", "wangtang", "jack", "gunrock", "galuda", "ayame", "rouge", "kraken", "valgas", "finalvalgas"]

func _put(s: Stub, r: Dictionary, lvl: int) -> void:
	s.global_position = Vector3(float(r.x), float(r.y), float(r.z)) * 0.01
	s.vcm = Vector3(float(r.vx), float(r.vy), float(r.vz))
	s.velocity = s.vcm * 0.6
	var a := float(int(r.ang)) / 65536.0 * TAU
	s.facing = Vector3(sin(a), 0, cos(a))
	s.ai_st = int(r.st); s.ai_hid = int(r.hid); s.powered = int(r.pc) != 0
	s.hp = int(r.hp); s.gems = int(r.gems); s.cpu_level = lvl

func _initialize() -> void:
	CPUGame.load_data()
	var path := OS.get_environment("PS_CPU_REPLAY")
	var rows: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		if line.strip_edges() != "": rows.append(JSON.parse_string(line))
	var n := mini(rows.size(), int(OS.get_environment("PS_REPLAY_N")) if OS.has_environment("PS_REPLAY_N") else rows.size())
	var st := [Stub.new(), Stub.new()]
	st[0].opponent = st[1]; st[1].opponent = st[0]
	var cs := []
	for i in 2:
		st[i].char_id = NAMES[int(rows[0].p[i].ch)]
		var c := CPUGame.new(st[i], null, int(rows[0].lvl))
		c.fight_index = int(OS.get_environment("PS_FIGHT")) if OS.has_environment("PS_FIGHT") else 0
		cs.append(c)
	var first := [-1, -1]; var same := [0, 0]; var same_btn := [0, 0]; var tot := [0, 0]
	var sel_same := [0, 0]; var sel_tot := [0, 0]
	var by_mode := [{}, {}]   # the disc's Mode at its selections -> [matched, total]
	var started := false
	for f in range(1, n):
		var pr: Dictionary = rows[f - 1]; var r: Dictionary = rows[f]
		if int(r.phase) != 3 and not started: continue
		started = true
		for i in 2: _put(st[i], pr.p[i], int(pr.lvl))
		CPUGame.rand_state = int(pr.rand)
		for i in 2:
			var c: CPUGame = cs[i]
			var o: Dictionary = r.p[i]
			if int(o.ch) == 10: continue   # Final Valgas: his own AI (not ported)
			c.mv_ok = int(r.mvok)
			if c.mv_ok == 0: c.pad = 0; c.prev = 0; continue
			c.level = int(pr.lvl)
			var t_before: int = c.table; var m_before: int = c.mode
			c.tick(1.0 / 60.0, Basis.IDENTITY)
			tot[i] += 1
			var ok_sel: bool = c.mode == int(o.mode) and c.intlv == int(o.intlv) and c.table == int(o.tbl)
			var ok_btn: bool = (c.pad & 0x604) == (int(o.pad) & 0x604)
			if ok_sel: same[i] += 1
			if ok_btn: same_btn[i] += 1
			if int(o.tbl) != int(pr.p[i].tbl) or int(o.mode) != int(pr.p[i].mode):   # the original selected a script
				sel_tot[i] += 1
				if ok_sel: sel_same[i] += 1
				var mk := "%02x" % int(o.mode)
				var e: Array = by_mode[i].get(mk, [0, 0]); e[1] += 1
				if ok_sel: e[0] += 1
				by_mode[i][mk] = e
			if first[i] < 0 and not (ok_sel and ok_btn):
				first[i] = f
				print("P%d first divergence at frame %d: port mode %x intlv %x tbl %d pad %x | disc mode %x intlv %x tbl %d pad %x (prev frame: port %x/%d disc %x/%d)" % [
					i + 1, f, c.mode, c.intlv, c.table, c.pad, int(o.mode), int(o.intlv), int(o.tbl), int(o.pad), m_before, t_before,
					int(pr.p[i].mode), int(pr.p[i].tbl)])
			if not ok_sel:   # follow the disc: take over its selection so the next frames compare like for like
				pass
	for i in 2:
		if tot[i] == 0: continue
		print("P%d %s: %d frames, Mode/IntLv/Table equal %.1f%%, buttons equal %.1f%%, script selections matched %d of %d, first divergence frame %d" % [
			i + 1, st[i].char_id, tot[i], 100.0 * same[i] / tot[i], 100.0 * same_btn[i] / tot[i], sel_same[i], sel_tot[i], first[i]])
		print("   selections by the disc's Mode [matched, total]: ", by_mode[i])
	quit(0)
