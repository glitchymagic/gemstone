extends Node
## Autoload "Game": settings and screen flow (title -> select -> fight -> results).

var quality := 2          # Look.PRESETS index
var cinematics := false   # Power Change / fusion / KO cinematics, impact sparks: a Pass-5 extra, Off by default = the
						  # original's presentation (the owner: extras never change the default Arcade / VS flow); title menu
var look := "remaster"    # HD.LOOKS: remaster (pass 6, stylized PBR) or classic (the pass 1-5 toon look)
var impact_fx := true     # Remaster: chromatic-aberration pulse on big hits
var mode := "versus"      # "arcade" (the original ladder) or "versus"
var chars := ["falcon", "ryoma"]
var cpu := [false, true]
var teams := [0, 1]       # Battle Royale: team per fighter (free-for-all = own team each)
var pads := [0, 1]
var kbs := [0, 1]
var brawl_stage := ""
var lighting := "original"    # remix lighting: original (default) | night | sunset | storm
var last_result := {}
var last_replay := ""     # the match just played (user://replays/*.psr)
var current: Node = null
# Arcade: the original ladder, logged from the game itself (tools/ladder.py -> assets/ripped/ladder.json):
# [{"opp": roster id, "stage": "stgN0"}, ...] in the order the game serves them (mirror match included, as the original).
var ladder: Array = []
var arcade_step := 0
var arcade_time_f := 0    # the arcade run's elapsed TIME (HUD top-left, fight frames), carried from fight to fight

const ArcadeFlow := preload("res://scripts/arcade_flow.gd")
var continuing := false   # CONTINUE? was answered: the select screen's pick fights the same opponent again

func start_arcade(p1: String) -> void:
	if continuing and not ladder.is_empty():
		continuing = false
		chars = [p1, ""]; cpu = [false, true]
		next_arcade_fight(); return
	ladder = Roster.load_ladder()
	arcade_step = 0; arcade_time_f = 0
	chars = [p1, ""]
	cpu = [false, true]
	next_arcade_fight()

func next_arcade_fight() -> void:
	while arcade_step < ladder.size() and not Roster.playable(ladder[arcade_step].opp):
		arcade_step += 1   # opponents not ripped yet are skipped (never replaced by a stand-in)
	if arcade_step >= ladder.size():
		last_result = {"arcade_clear": true, "chars": chars.duplicate()}
		goto_results(); return
	chars[1] = ladder[arcade_step].opp
	start_fight()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless": return

func _set_screen(n: Node) -> void:
	var root := get_tree().root
	if current and is_instance_valid(current): current.queue_free()
	current = n
	root.add_child.call_deferred(n)

func goto_title() -> void:
	get_tree().paused = false
	_set_screen(TitleScreen.new())

func goto_select() -> void:
	_set_screen(SelectScreen.new())

func start_brawl(p_chars: Array, p_cpu: Array, p_teams: Array, p_pads: Array, p_kbs: Array, stage: String) -> void:
	mode = "brawl"
	chars = p_chars.duplicate(); cpu = p_cpu.duplicate(); teams = p_teams.duplicate()
	pads = p_pads.duplicate(); kbs = p_kbs.duplicate(); brawl_stage = stage
	start_fight()

## Attract mode: the title screen left alone for 20 s plays a CPU-vs-CPU match (random fighters, stage and lighting; now
## and then a 4-fighter Battle Royale), cinematics as set in the title menu (Off by default, like the original's demo).
## Any button goes back to the title.
func start_attract() -> void:
	mode = "attract"
	var ids := Roster.selectable().filter(func(c): return Roster.playable(c.id)).map(func(c): return c.id)
	ids.shuffle()
	var n := 4 if randf() < 0.3 and ids.size() >= 4 else 2
	chars = ids.slice(0, n); cpu = []; teams = []
	for i in n: cpu.append(true); teams.append(i)
	brawl_stage = Roster.home_stage(ids[randi() % ids.size()])
	lighting = ["original", "original", "night", "sunset", "storm"][randi() % 5]
	start_fight()

func goto_brawl() -> void:
	_set_screen(BrawlSetup.new())

func start_fight() -> void:
	var f := Fight.new()
	f.chars = chars.duplicate()
	f.stage = (str(ladder[arcade_step].stage).to_lower() if mode == "arcade" and arcade_step < ladder.size()
		else (brawl_stage if mode == "brawl" and brawl_stage != "" else Roster.home_stage(chars[1] if mode != "brawl" else chars[0])))
	f.cpu_flags = cpu.duplicate()
	f.lighting = lighting
	if mode == "attract":
		f.attract = true; f.stage = brawl_stage; f.teams = teams.duplicate()
	if mode == "brawl":
		f.teams = teams.duplicate(); f.pads = pads.duplicate(); f.kbs = kbs.duplicate()
	if mode == "arcade": f.arcade_step = arcade_step; f.elapsed_f = arcade_time_f
	if mode == "training": f.training = true; f.cpu_flags = [false, true]
	f.match_over.connect(func(w, st):
		if mode == "attract":
			lighting = "original"; goto_title(); return
		if mode == "arcade":   # the original's automatic screens: next fight / continue countdown (scripts/arcade_flow.gd)
			arcade_time_f = f.elapsed_f
			last_result = {"winner": w, "stats": st, "chars": chars.duplicate(), "rounds": f.round_log.duplicate(),
				"teams": f.teams.duplicate(), "arcade": true, "step": arcade_step, "steps": ladder.size()}
			var af = ArcadeFlow.new()
			if w == 0:
				arcade_step += 1
				if arcade_step >= ladder.size(): next_arcade_fight(); return   # cleared: the results' ARCADE CLEAR
				af.kind = "boss" if str(ladder[arcade_step].opp) == "finalvalgas" and str(chars[1]) == "valgas" else "next"
			else: af.kind = "continue"
			_set_screen(af); return
		last_result = {"winner": w, "stats": st, "chars": chars.duplicate(), "rounds": f.round_log.duplicate(), "teams": f.teams.duplicate(),
			"arcade": mode == "arcade", "step": arcade_step, "steps": ladder.size()}
		goto_results())
	_set_screen(f)

func continue_arcade() -> void:
	continuing = true
	goto_select()

func goto_replays(p := "") -> void:
	var t := ReplayTheater.new(); t.path = p
	_set_screen(t)

func goto_results() -> void:
	_set_screen(ResultsScreen.new())
