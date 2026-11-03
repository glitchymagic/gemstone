extends RefCounted
## Replay theater, headless (after the cinematic match in run_tests.gd): save/load round trip, frames put back on the
## display fighters / stones / camera, free camera + photo mode, the highlight picker, render mode stepping.

var t: SceneTree
var fight: Fight
var th: ReplayTheater
var rd: ReplayTheater
var r: Replay
var n := 0
var finished := false
var hl := Vector2i.ZERO

func _init(runner: SceneTree, f: Fight) -> void:
	t = runner; fight = f

## The recording round trip uses its own file per checkout and look (every worktree shares user://, and test_all runs
## both looks at once: one shared user://replays/_test_cine.psr made the other run load a half-written file), outside
## the replay list.
var psr := "user://test_tmp/cine_%s_%s_%d.psr" % [ProjectSettings.globalize_path("res://").md5_text().substr(0, 8), OS.get_environment("PS_LOOK"), OS.get_process_id()]   # + pid: parallel runs of one look from one checkout

func check(c: bool, what: String) -> void:
	t.call("check", c, what)

func tick() -> void:
	n += 1
	match n:
		1:
			print("== replay theater")
			var p := fight.rec.save(psr)
			r = Replay.load_file(p)
			check(r != null and r.frames.size() == fight.rec.frames.size() and r.events.size() == fight.rec.events.size(), "replay saves + loads (%d frames)" % (r.frames.size() if r else 0))
			if r == null: finished = true; return
			var a: Array = fight.rec.frames[100].f[0]; var b: Array = r.frames[100].f[0]
			check(str(a) == str(b), "a frame survives the round trip")
			hl = r.pick_highlight()
			var secs := (hl.y - hl.x) / 60.0
			var kinds := {}
			for e in r.events: if int(e.f) >= hl.x and int(e.f) <= hl.y: kinds[e.kind] = true
			check(secs >= 14.9 and secs <= 25.1 and (kinds.has("ko") or kinds.has("power")), "highlight picks %.1f s with %s" % [secs, str(kinds.keys())])
			fight.queue_free()
			th = ReplayTheater.new(); th.path = p
			t.root.add_child(th)
		3:
			check(th.rep != null and th.fighters.size() == 2 and th.arena != null, "theater builds the stage + display fighters")
			var k := hl.x + 60
			th.playing = false; th.head = k; th._show(k)
			var s: Dictionary = th.rep.frames[k]
			var d: Array = s.f[1]
			check(th.fighters[1].global_position.distance_to(Vector3(d[0], d[1], d[2])) < 0.001 and th.fighters[1].hp == int(d[7]), "frame put back: position + health")
			check(th.cam.global_transform.origin.distance_to(Replay.cam_transform(s).origin) < 0.001, "recorded camera")
			var shown := 0
			for g in th.gem_nodes: if g.visible: shown += 1
			check(shown == (s.get("g", []) as Array).size(), "stones put back (%d)" % shown)
			check(th.fighters[1].model is PSModel and (th.fighters[1].model as PSModel).posing, "recorded clips posed")
			th._enter_free_cam(); th.yaw += 1.0; th._show(k + 1); th._place_free_cam()
			check(th.cam.global_transform.origin.distance_to(Replay.cam_transform(th.rep.frames[k + 1]).origin) > 0.1, "free camera leaves the recorded one")
			th._toggle_photo(); th._dof()
			check(th.photo and not th.playing and (th.cam.attributes as CameraAttributesPractical).dof_blur_far_enabled, "photo mode: paused, depth of field")
			var before := th.head
			th._toggle_photo(); th.playing = true
			th._jump(1)
			check(th.head > before, "jump to the next moment")
		5:
			th.queue_free()
			rd = ReplayTheater.new(); rd.render = true; rd.quit_at_end = false
			rd.segments = [{"psr": ProjectSettings.globalize_path(psr), "from": hl.x, "to": hl.x + 30}]
			t.root.add_child(rd)
		40:
			check(rd.render_done and rd.title_card.text.contains("vs"), "render mode plays the segment once (title '%s')" % rd.title_card.text)
			check(Highlight.kbps_for(25.0) * 25.0 / 8192.0 + 0.16 * 25.0 / 8.0 < 30.0, "MP4 bitrate keeps 25 s under 30 MB")
			rd.queue_free()
			finished = true
