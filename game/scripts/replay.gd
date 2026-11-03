class_name Replay
extends RefCounted
## Match recording: one snapshot per physics frame of everything on screen (fighter transforms, clip + time, form,
## hp, gems, gauge, props, Power Stones, camera, cinematic post-process, fx events). Playback just puts snapshots
## back, so it needs no determinism. Saved compressed under user://replays/ (*.psr).

const DIR := "user://replays/"
const VERSION := 1

var meta := {}           # version, stage, chars, cpu, teams, date, fps
var frames: Array = []   # one Dictionary per physics frame (see capture)
var events: Array = []   # highlight markers: {"f": frame, "kind": power|fusion|ko|hit|throw, "who": i, "dmg": n}
var pending_fx: Array = []
var paused := false      # the in-fight instant replay doesn't record itself

func begin(fight: Fight) -> void:
	meta = {"version": VERSION, "stage": fight.stage, "chars": fight.chars.duplicate(), "cpu": fight.cpu_flags.duplicate(),
		"teams": fight.teams.duplicate(), "date": Time.get_datetime_string_from_system(), "fps": 60, "lighting": fight.lighting}
	frames.clear(); events.clear(); pending_fx.clear()

func mark(kind: String, who: int, dmg := 0) -> void:
	events.append({"f": frames.size(), "kind": kind, "who": who, "dmg": dmg})

func fx_event(kind: String, pos: Vector3, val := 0.0) -> void:
	pending_fx.append([kind, pos.x, pos.y, pos.z, val])

func capture(fight: Fight) -> void:
	if paused: return
	var fs := []
	for f in fight.fighters:
		var ms: Array = (f.model as PSModel).snapshot() if f.model is PSModel else [false, "", 0.0, 0.0, 0.0]
		var p := f.global_position
		fs.append([p.x, p.y, p.z, f.model.rotation.y if f.model else 0.0, ms[0], ms[1], ms[2], f.hp, f.gems, f.gauge,
			f.state, f.powered, snappedf(ms[3], 0.001), snappedf(ms[4], 0.001)])
	var ps := []
	for pr in fight.arena.props:
		var n := pr as Node3D
		ps.append([n.position.x, n.position.y, n.position.z, n.rotation.x, n.rotation.y, n.rotation.z, n.visible])
	var gs := []
	for g in fight.arena.gems:
		gs.append([g.global_position.x, g.global_position.y, g.global_position.z, g.color_idx])
	var ct := fight.cam.global_transform
	var snap := {"ph": fight.phase, "tm": fight.timer, "rd": fight.round_no, "w": fight.wins.duplicate(), "f": fs, "p": ps,
		"g": gs, "c": [ct.basis.x, ct.basis.y, ct.basis.z, ct.origin, fight.cam.fov]}
	if fight.cinema: snap["x"] = fight.cinema.post_state()
	if not pending_fx.is_empty():
		snap["e"] = pending_fx.duplicate(); pending_fx.clear()
	frames.append(snap)

static func cam_transform(snap: Dictionary) -> Transform3D:
	var c: Array = snap.c
	return Transform3D(Basis(c[0], c[1], c[2]), c[3])

## Put frame `snap` on display-only fighters / props / gems (the viewer's, or the live ones during the instant replay).
static func apply_fighters(snap: Dictionary, fighters: Array) -> void:
	var fs: Array = snap.f
	for i in mini(fs.size(), fighters.size()):
		var d: Array = fs[i]
		var f: Fighter = fighters[i]
		f.global_position = Vector3(d[0], d[1], d[2])
		if f.model:
			f.model.rotation.y = d[3]
			if f.model is PSModel: (f.model as PSModel).pose(d[4], d[5], d[6], Vector2(d[12], d[13]) if d.size() > 13 else Vector2.ZERO)

static func apply_props(snap: Dictionary, props: Array) -> void:
	var ps: Array = snap.p
	for i in mini(ps.size(), props.size()):
		var d: Array = ps[i]
		var n: Node3D = props[i]
		n.position = Vector3(d[0], d[1], d[2]); n.rotation = Vector3(d[3], d[4], d[5]); n.visible = d[6]

func save(path := "") -> String:
	DirAccess.make_dir_recursive_absolute(DIR if path == "" else path.get_base_dir())
	if path == "":
		path = DIR + "match_%s_%d.psr" % [Time.get_datetime_string_from_system().replace(":", "-"), OS.get_process_id()]   # two games saving in one second (parallel test runs) never share a file
	var fa := FileAccess.open_compressed(path, FileAccess.WRITE, FileAccess.COMPRESSION_ZSTD)
	if fa == null: return ""
	fa.store_var({"meta": meta, "frames": frames, "events": events})
	fa.close()
	return path

static func load_file(path: String) -> Replay:
	var fa := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_ZSTD)
	if fa == null: return null
	var d = fa.get_var()
	fa.close()
	if not (d is Dictionary and d.has("frames")): return null
	var r := Replay.new()
	r.meta = d.meta; r.frames = d.frames; r.events = d.events
	return r

static func list_saved() -> Array:   # newest first
	var out := []
	var da := DirAccess.open(DIR)
	if da == null: return out
	for fn in da.get_files():
		if fn.ends_with(".psr"): out.append(DIR + fn)
	out.sort()
	out.reverse()
	return out

## Highlight: the best 15-25 s window of the match by its marked moments (Power Change, fusion, KO, heavy hits), with
## enough tail after the last moment for its cinematic (Power Change 2.2 s, KO slow motion + the winner's pose ~3.6 s).
const SCORE := {"power": 10.0, "fusion": 6.0, "ko": 14.0}
const TAIL := {"power": 150, "fusion": 70, "ko": 216, "hit": 30}

func pick_highlight(min_s := 15.0, max_s := 25.0) -> Vector2i:
	var fps := int(meta.get("fps", 60))
	var n := frames.size()
	if n <= int(min_s * fps): return Vector2i(0, n - 1)
	var pts := []
	for e in events:
		var sc: float = SCORE.get(e.kind, 0.0)
		if e.kind == "hit": sc = maxf(0.0, (Rules.dmg_1000(e.dmg) - 50.0) / 40.0)
		if sc > 0.0: pts.append([int(e.f), sc, String(e.kind)])
	var best := Vector2i(maxi(0, n - int(max_s * fps)), n - 1); var bs := -1.0
	for p in pts:
		var end := mini(n - 1, int(p[0]) + int(TAIL.get(p[2], 30)))
		for secs in [min_s, (min_s + max_s) * 0.5, max_s]:
			var start := maxi(0, end - int(secs * fps))
			if end - start < int(min_s * fps): end = mini(n - 1, start + int(min_s * fps))
			var sc := 0.0
			for q in pts:
				if int(q[0]) >= start + 30 and int(q[0]) + int(TAIL.get(q[2], 30)) * 0.5 <= end: sc += float(q[1])
			sc -= (secs - min_s) * 0.25   # same moments in less time is better
			if p[2] == "ko": sc += 6.0       # and end on a KO
			if sc > bs: bs = sc; best = Vector2i(start, end)
	return best
