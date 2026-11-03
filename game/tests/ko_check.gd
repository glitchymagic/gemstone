extends SceneTree
## Round-end freeze proof (BUG-2): one seeded CPU-vs-CPU match in the real flow (HUD, KO timings, cinematics on or off),
## every frame from each KO to the next round checked by tests/ko_watch.gd.
## Godot --headless --path game --fixed-fps 60 -s res://tests/ko_check.gd -- STAGE a,b [MAX_FRAMES]
## env: PS_SEED=n, PS_CINE=1|0 (default 1). Prints KO_CHECK <stage> <a,b> cine=<0|1> ... and quits 1 s after the match.
var n := 0
var end_at := -1
var max_f := 60 * 60 * 8
var f: Fight
var w

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	f = Fight.new(); f.cpu_flags = [true, true]; f.no_replay = true
	f.cine_force = OS.get_environment("PS_CINE") != "0"
	f.stage = str(a[0]); f.chars = Array(str(a[1]).split(","))
	if a.size() > 2: max_f = int(a[2])
	if OS.has_environment("PS_SEED"): f.seed_override = int(OS.get_environment("PS_SEED"))
	f.match_over.connect(func(_w, _s): end_at = n + 60)
	var g := root.get_node_or_null("Game")
	if g: g.set("cinematics", false)   # cinematics only when forced
	root.add_child(f)
	w = load("res://tests/ko_watch.gd").new(f)

func _process(_d: float) -> bool:
	n += 1
	w.tick()
	if OS.has_environment("PS_KO_TRACE") and w.on:
		var ln := "T %d ph%d %s" % [n, f.phase, f.cinema.kind if f.cinema else "-"]
		for x in f.fighters:
			var m := x.model as PSModel
			ln += " | %s st%d hp%d clip=%s pos=%.2f play=%s ts=%.2f posing=%d" % [x.char_id, x.state, x.hp, w.clip_of(m), m.clip_pos(), m.playing, m.time_scale, int(m.posing)]
		print(ln)
	if (end_at > 0 and n >= end_at) or n >= max_f:
		print("KO_CHECK %s %s cine=%d seed=%s rounds=%d frames=%d: %s %s" % [f.stage, ",".join(f.chars), int(f.cinema != null),
			OS.get_environment("PS_SEED"), f.round_log.size(), n, w.report(), "OK" if w.ok() and end_at > 0 else "FAIL"])
		quit(0 if w.ok() and end_at > 0 else 1)
		return true
	return false
