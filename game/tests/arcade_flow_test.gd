extends SceneTree
## fx-flow: the arcade's screens between fights on the original's frames (docs/FLOW.md), through the real Game autoload:
## fight 1 won (P2 KO'd twice) -> the STAGE / VS screen for 1036 frames -> fight 2; fight 2 lost (P1 KO'd twice) ->
## CONTINUE? left alone for 1002 frames -> THE END 307 frames -> title. Also the round phases of fight 1 (intro 310,
## Ready 152, poses 245 / 307) and the HUD's arcade TIME carried into fight 2.
## Godot --headless --path game --fixed-fps 60 -s res://tests/arcade_flow_test.gd
var g: Node
var n := 0
var passes := 0
var fails := 0
var last: Node = null
var since := 0
var seen := []          # [screen kind, frames it lasted]
var last_phase := -1
var phase_n := 0
var fights := 0
var t_carry := -1
var last_kind := "none"
var ph_seq := []        # fight 1: [phase name, frames] in order

func check(c: bool, what: String) -> void:
	if c: passes += 1
	else:
		fails += 1; printerr("FAIL: ", what)

func _initialize() -> void:
	g = root.get_node_or_null("Game")

func _kind(s: Node) -> String:
	if s is Fight: return "fight"
	if s != null and s.get_script() == load("res://scripts/arcade_flow.gd"): return "flow_" + str(s.get("kind"))
	if s is TitleScreen: return "title"
	return s.get_class() if s else "none"

func _physics_process(_d: float) -> bool:
	n += 1
	if n == 2: g.set("mode", "arcade"); g.call("start_arcade", "ryoma")   # the autoload is in the tree from the first frame
	if n <= 2: return false
	var cur: Node = g.get("current")
	if cur != last:
		if since > 0: seen.append([last_kind, since])
		if last_kind == "fight" and fights == 1 and last_phase >= 0: ph_seq.append([Fight.R.keys()[last_phase], phase_n])
		last = cur; since = 0; last_kind = _kind(cur)
		print("frame %d: screen %s" % [n, last_kind])
		if cur is Fight: fights += 1
	since += 1
	if cur is Fight and cur.is_inside_tree():
		var f := cur as Fight
		if f.phase != last_phase:
			if fights == 1 and last_phase >= 0: ph_seq.append([Fight.R.keys()[last_phase], phase_n])
			last_phase = f.phase; phase_n = 0
		phase_n += 1
		if fights == 2 and t_carry < 0: t_carry = f.elapsed_f
		if f.phase == Fight.R.FIGHT and f.pf >= 30 and f.ko_f < 0:   # KO the loser of this fight from its 30th fight frame on
			var v: Fighter = f.fighters[1] if fights == 1 else f.fighters[0]
			var a: Fighter = f.fighters[0] if fights == 1 else f.fighters[1]
			v.invuln = 0.0
			v.receive_hit(999, 8.0, true, a.global_position, a)
	if _kind(cur) == "title" or n > 60 * 60 * 4:
		seen.append([last_kind, since])
		print("screens: ", seen)
		print("fight 1 phases: ", ph_seq)
		var lens := {}
		for e in ph_seq: lens[e[0]] = lens.get(e[0], []) + [e[1]]
		var ks := seen.map(func(s): return s[0])
		check(ks.slice(0, 5) == ["fight", "flow_next", "fight", "flow_continue", "title"], "won > STAGE/VS > fight > CONTINUE? > title (%s)" % str(ks))
		for s in seen:
			if s[0] == "flow_next": check(absi(int(s[1]) - 1036) <= 2, "STAGE/VS screen 1036 frames (%d)" % s[1])
			if s[0] == "flow_continue": check(absi(int(s[1]) - (1002 + 307)) <= 3, "CONTINUE? 1002 + THE END 307 frames (%d)" % s[1])
		# (this script samples before the fight's own frame: the first phase reads one frame long)
		check(lens.get("INTRO", [0])[0] in [310, 311], "intro 310 frames (%s)" % str(lens.get("INTRO")))
		check(lens.get("READY", []) == [152, 152], "Ready 152 frames, both rounds (%s)" % str(lens.get("READY")))
		check(lens.get("ROUND_END", []) == [245, 307], "poses 245, then 307 (match won by P1) (%s)" % str(lens.get("ROUND_END")))
		check(lens.get("KO", [0, 0]).all(func(v): return v >= 151), "KO phase: the 151-frame freeze + quarter speed at least (%s)" % str(lens.get("KO")))
		check(t_carry > 0, "the arcade TIME carries into fight 2 (%d frames)" % t_carry)
		print("TOTAL: %d passed, %d failed" % [passes, fails])
		quit(0 if fails == 0 else 1)
		return true
	return false
