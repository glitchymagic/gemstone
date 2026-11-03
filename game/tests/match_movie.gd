extends SceneTree
## One full CPU-vs-CPU match as a player sees it (HUD, music, cinematics), for Godot's Movie Maker.
## Godot --path game --fixed-fps 60 --write-movie OUT.avi -s res://tests/match_movie.gd -- STAGE a,b [MAX_FRAMES]
## env: PS_SEED=n (repeatable fight), PS_LOOK, PS_PRESET (1 = Medium, what the PC plays), PS_LIGHT,
## PS_AUDIT=file: one JSON line per frame of what the player sees (scripts/cam_check.gd; tools/cam_audit.py reads it).
## Quits 5 s after the match ends (winner pose) or at MAX_FRAMES (default 4 min).
var n := 0
var end_at := -1
var max_f := 60 * 240
var f: Fight
var audit: FileAccess

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	f = Fight.new(); f.cpu_flags = [true, true]; f.cine_force = true
	f.stage = str(a[0]); f.chars = Array(str(a[1]).split(","))
	if a.size() > 2: max_f = int(a[2])
	if OS.has_environment("PS_SEED"): f.seed_override = int(OS.get_environment("PS_SEED"))
	if OS.has_environment("PS_LIGHT"): f.lighting = OS.get_environment("PS_LIGHT")
	f.match_over.connect(_on_over)
	root.add_child(f)
	if OS.has_environment("PS_AUDIT"): audit = FileAccess.open(OS.get_environment("PS_AUDIT"), FileAccess.WRITE)

func _on_over(w: int, _s) -> void:
	print("MATCH_OVER winner P%d at frame %d" % [w + 1, n])
	end_at = n + 300

func _process(_d: float) -> bool:
	n += 1
	if n % 600 == 0: print("FRAME %d" % n)
	if audit and f.is_inside_tree() and f.cam: audit.store_line(JSON.stringify(CamCheck.frame(f, n)))
	if (end_at > 0 and n >= end_at) or n >= max_f:
		print("MOVIE_END frame %d" % n)
		if audit: audit.close()
		quit()
		return true
	return false
