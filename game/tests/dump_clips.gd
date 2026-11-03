extends SceneTree
## Every fighter's captured motion clips -> frames (length * 60), for the fidelity core's motion lengths.
## Godot --headless --path game -s res://tests/dump_clips.gd -- OUT.json
func _initialize() -> void:
	var out := {}
	for c in Roster.ALL:
		var m := PSModel.create_for(str(c.id), false)
		if m == null: continue
		var d := {}
		for f in m.players.keys():
			var ap: AnimationPlayer = m.players[f]
			for an in ap.get_animation_list():
				d[String(an)] = int(round(ap.get_animation(an).length * 60.0))
		out[str(c.id)] = d
		m.free()
	var fa := FileAccess.open(OS.get_cmdline_user_args()[0], FileAccess.WRITE)
	fa.store_string(JSON.stringify(out, " ", true))
	fa.close()
	print("CLIPS ", out.size())
	quit()
