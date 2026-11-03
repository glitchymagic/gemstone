extends SceneTree
const QuietExit = preload("res://tests/quiet_exit.gd")
## fx-flow proof: the remaster's round flow logged per frame (Fight.flow_row: phase as the original's round phase byte,
## MV_OK, clock, both fighters' game state / motion kind+id / health) for the same scenario as the Flycast logs of
## tools/flowlog.py, then compared by tools/flow_diff.py (phase lengths + motion sequence per phase).
## Godot --headless --path game --fixed-fps 60 -s res://tests/flow_run.gd -- ko|time OUT.jsonl
##   ko   = o_round's first fight: Ryoma (P1, CPU) vs Falcon (CPU) on Londo, P2 at 20 health every round, P1 at 200 in
##          round 1 -> a 2-round KO match
##   lose = o_screens' fight: Falcon (P1, nobody at the pad) at 10 health every round vs Wang-Tang (CPU) on his stage ->
##          P1 KO'd twice (the CPU wins the match: phase 5 275)
##   time = o_round's second fight: Ryoma vs Ayame on her stage, nobody moves; round 1 clock set to 4 s at the first
##          fight frame (the Flycast run poked the clock byte to 4), round 2 runs the full 99 s -> two TIME draws
var f: Fight
var n := 0
var mode := "ko"
var end_at := -1
var last_round := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	mode = str(a[0])
	OS.set_environment("PS_FLOW_LOG", str(a[1]))
	OS.set_environment("PS_SEED", "7")
	f = Fight.new(); f.test_mode = true; f.no_replay = true
	if mode == "ko":
		f.chars = ["ryoma", "falcon"]; f.stage = "stg00"; f.cpu_flags = [true, true]
	elif mode == "lose":
		f.chars = ["falcon", "wangtang"]; f.stage = "stg20"; f.cpu_flags = [false, true]
	else:
		f.chars = ["ryoma", "ayame"]; f.stage = "stg60"; f.cpu_flags = [false, false]
	f.match_over.connect(func(_w, _s): end_at = n + 2)
	root.add_child(f)

func _physics_process(_d: float) -> bool:
	n += 1
	if f.is_inside_tree() and f.phase == Fight.R.FIGHT and f.pf == 1 and last_round != f.round_no:
		last_round = f.round_no
		if mode == "ko":
			f.fighters[1].hp = 20
			if f.round_no == 1: f.fighters[0].hp = 200
		elif mode == "lose":
			f.fighters[0].hp = 10
		elif f.round_no == 1:
			f.fight_t = (Rules.ROUND_TIME - 4.0) * Fight.FL_SEC + 1.0   # one fight frame already ran (the poke's frame)
	if (end_at > 0 and n >= end_at) or n > 60 * 400:
		if f.flow_log: f.flow_log.close(); f.flow_log = null
		print("FLOW_END frame %d phase %d rounds %s" % [n, f.phase, str(f.round_log)])
		QuietExit.drain(root)   # BUG-38: stop the sounds + let the audio thread free their playbacks (--fixed-fps outruns it)
		quit()
		return true
	return false
