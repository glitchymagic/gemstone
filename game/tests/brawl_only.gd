extends SceneTree
## Runs only tests/brawl_tests.gd (Battle Royale FFA + 2v2) without the rest of run_tests.gd.
## Godot --headless --path game --fixed-fps 60 -s res://tests/brawl_only.gd [-- falcon,ryoma stg00]
var b: RefCounted
var passes := 0
var fails := 0
var n := 0

func check(c: bool, what: String) -> void:
	if c: passes += 1
	else:
		fails += 1; printerr("FAIL: ", what)

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	b = load("res://tests/brawl_tests.gd").new(self, Array(str(a[0]).split(",")) if a.size() > 0 else ["falcon", "ryoma"], str(a[1]) if a.size() > 1 else "stg00")

func _process(_d: float) -> bool:
	n += 1
	if n % 3600 == 0 and b.fight and is_instance_valid(b.fight):
		print("t=%d s phase %d round %d timer %.0f log %s" % [n / 60, b.fight.phase, b.fight.round_no, b.fight.timer, str(b.fight.round_log.map(func(r): return [r.winner, r.how]))])
	if not b.finished: b.tick(); return false
	print("TOTAL: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
	return true
