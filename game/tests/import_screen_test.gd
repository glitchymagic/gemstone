extends SceneTree
## The first-run screen end to end: runs the importer on a disc dump the way the Choose button does, waits for it,
## checks the report the game reads back. Godot --path game -s res://tests/import_screen_test.gd -- DISC.gdi
var s: ImportScreen
var n := 0

func _initialize() -> void:
	s = ImportScreen.new()
	root.add_child(s)

func _process(_d: float) -> bool:
	n += 1
	if n == 2:
		s._run(OS.get_cmdline_user_args()[0])
		if s._thread == null: print("IMPORT_TEST FAIL no importer started: ", s._status.text); quit(1); return true
	if n > 2 and s._thread == null:
		var r := ImportScreen.report()
		var ok := 0
		for k in r.get("steps", {}): if r.steps[k].get("ok", false): ok += 1
		print("IMPORT_TEST steps ok %d / %d, complete %s, log lines %d, status: %s" % [ok, r.get("steps", {}).size(),
			str(r.get("complete", false)), s._log.get_parsed_text().count("\n"), s._status.text])
		quit(0 if ok > 0 else 1)
		return true
	if n > 60 * 900: print("IMPORT_TEST FAIL timeout"); quit(1); return true
	return false
