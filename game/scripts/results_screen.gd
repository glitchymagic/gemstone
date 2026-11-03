class_name ResultsScreen
extends Node3D
## Results: winner, rounds, per-player stats. Rematch / character select / title.

var ui: CanvasLayer
var music: AudioStreamPlayer

func _ready() -> void:
	Look.build_environment(self)
	var cam := Camera3D.new(); cam.current = true; add_child(cam)
	HD.light_rig(cam)
	var r: Dictionary = UI.game().get("last_result")
	var w: int = r.get("winner", -1)
	var chars: Array = r.get("chars", ["falcon", "ryoma"])
	var teams: Array = r.get("teams", range(chars.size()))
	var team_mode := false
	for i in teams.size(): if int(teams[i]) != i: team_mode = true
	var star := w   # the fighter on the podium: the winner, or the winning team's first
	if team_mode:
		star = -1
		for i in teams.size(): if int(teams[i]) == w and star < 0: star = i
	if star >= 0:
		var m := PSModel.create_for(chars[star], false)
		if m:
			add_child(m); m.play("win"); m.position = Vector3(1.2, -0.2, -3.5); m.rotation.y = -0.4
		cam.look_at_from_position(Vector3(0, 1.2, 1.5), Vector3(0.6, 0.9, -3.5))
		HD.hero(self, cam, Vector3(1.2, 0.8, -3.5), -0.2)
	ui = CanvasLayer.new(); add_child(ui)
	var v := VBoxContainer.new(); v.position = Vector2(120, 140)
	v.add_theme_constant_override("separation", 14)
	ui.add_child(v)
	var title := ("%s WINS!" % Roster.display_name(chars[w]).to_upper()) if w >= 0 and not team_mode else "DRAW"
	if team_mode and w >= 0: title = "TEAM %s WINS!" % ["RED", "BLUE"][clampi(w, 0, 1)]
	var tl := UI.label(title, 96, Color(1, 0.85, 0.25)); tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	v.add_child(tl)
	for rd in r.get("rounds", []):
		var who: String = "Draw" if rd.winner < 0 else (("Team " + ["Red", "Blue"][clampi(int(rd.winner), 0, 1)]) if team_mode else Roster.display_name(chars[rd.winner]))
		var l := UI.label("Round %d: %s (%s)" % [rd.round, who, rd.how], 32); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(l)
	var st: Array = r.get("stats", [])
	for i in st.size():
		var s: Dictionary = st[i]
		var l := UI.label("P%d %s  hits %d  damage %d  throws %d  objects %d  gems %d  power changes %d" % [i + 1,
			Roster.display_name(chars[i]), s.hits, s.dmg_dealt, s.throws, s.objects_thrown, s.gems_picked, s.changes], 26)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		v.add_child(l)
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 30); v.add_child(sp)
	var b1: Button
	if r.get("arcade_clear", false):
		tl.text = "ARCADE CLEAR!"
		b1 = UI.button("Title", func(): UI.game().call("goto_title"))
	elif r.get("arcade", false) and w == 0:
		b1 = UI.button("Next fight (%d / %d)" % [int(r.step) + 2, int(r.steps)], func():
			UI.game().set("arcade_step", int(r.step) + 1); UI.game().call("next_arcade_fight"))
	elif r.get("arcade", false):
		b1 = UI.button("Continue", func(): UI.game().call("start_fight"))
	else:
		b1 = UI.button("Rematch", func(): UI.game().call("start_fight"))
	v.add_child(b1)
	if String(UI.game().get("last_replay")) != "":
		v.add_child(UI.button("Watch replay", func(): UI.game().call("goto_replays", String(UI.game().get("last_replay")))))
	v.add_child(UI.button("Character select", func(): UI.game().call("goto_select")))
	v.add_child(UI.button("Title", func(): UI.game().call("goto_title")))
	b1.call_deferred("grab_focus")
	music = AudioStreamPlayer.new(); add_child(music)
	var s2 := Audio.music("WIN")
	if s2: music.stream = s2; music.play()
