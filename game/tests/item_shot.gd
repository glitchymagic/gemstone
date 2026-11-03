extends SceneTree
## fx-item2: windowed stills of a tape run (chests / items as the player sees them), Mac only.
## Godot --path game --resolution 1280x720 -s res://tests/item_shot.gd -- TAPE.txt STAGE p1,p2 /abs/out_prefix F1,F2,..
## (TAPE.txt = tools/tapes.py output, as tests/tape_run.gd). Saves out_prefix_F.png at each tape frame F.
var f: Fight
var shots: Array = []
var out := ""
var n := 0

func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	f = Fight.new(); f.cpu_flags = [false, false]; f.test_mode = true
	f.stage = str(a[1]); f.chars = Array(str(a[2]).split(","))
	out = str(a[3])
	for s in str(a[4]).split(","): shots.append(int(s))
	for ln in FileAccess.get_file_as_string(str(a[0])).split("\n"):
		var parts := ln.strip_edges().split(";")
		var w := parts[0].strip_edges().split(" ", false)
		if w.size() >= 2:
			var cmds := []
			for k in range(1, parts.size()): cmds.append(parts[k].strip_edges())
			f.tape.append([w[0].hex_to_int(), w[1].hex_to_int(), cmds])
	root.add_child(f)

func _process(_d: float) -> bool:
	n += 1
	if f.tape_f >= 0 and not shots.is_empty() and f.tape_f >= int(shots[0]):
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s_%d.png" % [out, int(shots[0])])
		shots.pop_front()
	if shots.is_empty() or n > 60 * 600:
		quit()
		return true
	return false
