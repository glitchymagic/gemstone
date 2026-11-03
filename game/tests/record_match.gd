extends SceneTree
## Records a full CPU-vs-CPU match with cinematics on, headless, into a replay file (for highlights / media).
## Godot --headless --path game --fixed-fps 60 -s res://tests/record_match.gd
## env: PS_OUT=/abs/out.psr  PS_CHARS=falcon,ryoma[,..]  PS_STAGE=stg00  PS_TEAMS=0,1[,..]  PS_LIGHT=night|storm|sunset (PS_LOOK=remaster|classic)
##      PS_SEED=n  PS_MAX_S=seconds (stop early: the replay is saved with what was recorded)
##      PS_AUDIT=/abs/audit.jsonl: what the player sees each frame (scripts/cam_check.gd, tools/cam_audit.py), "rf" = the
##      replay frame it describes (the camera a replay / highlight render shows for that frame)

var fight: Fight
var frames := 0
var out := "/tmp/match.psr"
var max_f := 60 * 60 * 6
var audit: FileAccess

func _initialize() -> void:
	if OS.has_environment("PS_OUT"): out = OS.get_environment("PS_OUT")
	if OS.has_environment("PS_MAX_S"): max_f = int(float(OS.get_environment("PS_MAX_S")) * 60)
	fight = Fight.new()
	fight.cine_force = true; fight.save_replay = true
	fight.chars = ["falcon", "ryoma"]
	if OS.has_environment("PS_CHARS"): fight.chars = Array(OS.get_environment("PS_CHARS").split(","))
	fight.cpu_flags = []
	for c in fight.chars: fight.cpu_flags.append(true)
	if OS.has_environment("PS_TEAMS"): fight.teams = Array(OS.get_environment("PS_TEAMS").split(",")).map(func(x): return int(x))
	if OS.has_environment("PS_STAGE"): fight.stage = OS.get_environment("PS_STAGE")
	if OS.has_environment("PS_LIGHT"): fight.lighting = OS.get_environment("PS_LIGHT")
	if OS.has_environment("PS_SEED"): fight.seed_override = int(OS.get_environment("PS_SEED"))
	fight.match_over.connect(func(w, _s): _finish("winner P%d" % (w + 1)))
	root.add_child(fight)
	if OS.has_environment("PS_AUDIT"): audit = FileAccess.open(OS.get_environment("PS_AUDIT"), FileAccess.WRITE)

func _finish(why: String) -> void:
	# straight from memory: copying the fight's own user://replays/match_<second>.psr raced when two recordings ran
	# at once (same second = same file, so one copy got the other match)
	var p := fight.rec.save(out)
	if audit: audit.close(); audit = null
	print("RECORDED %s: %s, %d frames, events %d (%s)" % [out, why, fight.rec.frames.size(), fight.rec.events.size(), p])
	quit()

func _process(_dt: float) -> bool:
	frames += 1
	if audit and fight.is_inside_tree() and fight.cam and not fight.rec.frames.is_empty() and fight.phase != Fight.R.DONE:
		var a := CamCheck.frame(fight, frames)
		a["rf"] = fight.rec.frames.size() - 1
		audit.store_line(JSON.stringify(a))
	if frames > max_f:
		_finish("stopped at %d s" % (max_f / 60)); return true
	return false
