extends SceneTree
## Runs only tests/cine_tests.gd (the cinematics match + KO / replay / win checks) without the rest of run_tests.gd.
## Godot --headless --path game --fixed-fps 60 -s res://tests/cine_only.gd [-- falcon,ryoma stg00]
var cine: RefCounted
var passes := 0
var fails := 0

func check(c: bool, what: String) -> void:
	if c: passes += 1
	else:
		fails += 1; printerr("FAIL: ", what)

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	cine = load("res://tests/cine_tests.gd").new(self)
	cine.start(Array(str(a[0]).split(",")) if a.size() > 0 else ["falcon", "ryoma"], str(a[1]) if a.size() > 1 else "stg00")

func _process(_d: float) -> bool:
	if not cine.finished: cine.tick(); return false
	print("TOTAL: %d passed, %d failed" % [passes, fails])
	quit(0 if fails == 0 else 1)
	return true
