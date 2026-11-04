class_name ImportScreen
extends Control
## First run: nothing from the game ships with the remaster, so this screen asks for the player's own disc dump and
## runs the importer (importer/psimport.py, or the bundled importer/gemstone-import.exe) on it. It shows the importer's
## output live, then what it could and couldn't make. The game starts only once everything the disc holds is imported;
## what the importer can't make yet (numbers measured from the original running, not files on the disc) is listed,
## never replaced by a stand-in.

const REPORT := "res://assets/IMPORT_REPORT.json"
var _log: RichTextLabel
var _status: Label
var _pick: Button
var _play: Button
var _dlg: FileDialog
var _thread: Thread
var _pid := -1

static func report() -> Dictionary:
	if not FileAccess.file_exists(REPORT): return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	return d if d is Dictionary else {}

static func needed() -> bool:
	return not bool(report().get("complete", false))

static func root_dir() -> String:   # the checkout / install folder (game/ is inside it)
	return ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new(); bg.color = Color(0.05, 0.05, 0.08)
	add_child(bg); bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	add_child(box); box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 120)
	box.add_theme_constant_override("separation", 18)
	var t := Label.new(); t.text = "GEMSTONE: a Power Stone remaster"; t.add_theme_font_size_override("font_size", 44)
	box.add_child(t)
	_status = Label.new(); _status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 24)
	box.add_child(_status)
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 16); box.add_child(row)
	_pick = Button.new(); _pick.text = "  Choose your disc (.gdi / .chd / .cdi)  "; _pick.add_theme_font_size_override("font_size", 24)
	_pick.pressed.connect(func(): _dlg.popup_centered_ratio(0.7))
	row.add_child(_pick)
	_play = Button.new(); _play.text = "  Play  "; _play.add_theme_font_size_override("font_size", 24)
	_play.pressed.connect(_restart); _play.visible = false
	row.add_child(_play)
	_log = RichTextLabel.new(); _log.size_flags_vertical = Control.SIZE_EXPAND_FILL; _log.scroll_following = true
	_log.custom_minimum_size = Vector2(0, 300); _log.fit_content = false
	_log.add_theme_font_size_override("normal_font_size", 20)
	box.add_child(_log)
	_dlg = FileDialog.new(); _dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE; _dlg.access = FileDialog.ACCESS_FILESYSTEM
	_dlg.filters = PackedStringArray(["*.gdi, *.chd, *.cdi ; Power Stone disc dump"])
	_dlg.file_selected.connect(_run)
	add_child(_dlg)
	_show_report(report())
	_pick.grab_focus()

func _show_report(r: Dictionary) -> void:
	if r.is_empty():
		_status.text = ("Point me at your Power Stone disc: a .gdi, .chd or .cdi dump of your own copy (Power Stone, USA). "
			+ "Nothing from the game comes with the remaster; the importer builds it all from your disc, on this computer.")
		return
	var miss := []
	for k in r.get("steps", {}):
		var s: Dictionary = r.steps[k]
		if k == "measured": continue
		if not s.get("ok", false): miss.append("- %s: %s" % [k, s.get("missing", s.get("error", "failed"))])
	var gi: Dictionary = r.get("godot_import", {})
	if not gi.get("ok", true): miss.append("- godot import: %s" % gi.get("error", "failed"))
	if miss.is_empty() and bool(r.get("complete", false)):
		_status.text = ("Everything on your disc is imported. Press Play. Not in this build yet (the game plays these "
			+ "parts by its own simpler rules until they are decoded):")
		_log.clear()
		var later: Dictionary = r.get("not_in_this_build", {})
		for k in later: _log.append_text("- %s: %s\n" % [k, later[k]])
		_play.visible = true; _play.grab_focus()
	else:
		_status.text = "Imported what the importer can make so far. Still missing, so the game can't start yet:"
		_log.clear()
		for m in miss: _log.append_text(m + "\n")

func _importer() -> Array:   # [program, leading args]
	var root := root_dir()
	for exe in ["importer/gemstone-import.exe", "importer/gemstone-import"]:
		if FileAccess.file_exists(root.path_join(exe)): return [root.path_join(exe), []]
	var py := root.path_join("importer/psimport.py")
	if OS.has_environment("PS_PYTHON"): return [OS.get_environment("PS_PYTHON"), [py]]
	for p in (["py", "python", "python3"] if OS.get_name() == "Windows" else ["python3", "python"]):
		var out := []
		if OS.execute(p, ["--version"], out, true) == 0: return [p, [py]]
	return []

func _run(path: String) -> void:
	var imp := _importer()
	if imp.is_empty():
		_status.text = "No importer found: install Python 3.10+ and run  pip install -r importer/requirements.txt"
		return
	var args: Array = imp[1] + [path, "--godot", OS.get_executable_path()]
	_pick.disabled = true
	_status.text = "Importing from your disc... First run: about 1 1/2 hours on a recent Mac, several hours on a PC without a GPU (the HD textures). Only once."
	_log.clear()
	var p := OS.execute_with_pipe(imp[0], PackedStringArray(args))
	if p.is_empty():
		_status.text = "Couldn't start the importer (%s)" % imp[0]; _pick.disabled = false; return
	_pid = p.pid
	_thread = Thread.new()
	_thread.start(_pump.bind(p.stdio as FileAccess, p.stderr as FileAccess))

func _pump(out: FileAccess, err: FileAccess) -> void:
	while out.is_open() and out.get_error() == OK:
		var l := out.get_line()
		if l != "": _line.call_deferred(l)
		elif not OS.is_process_running(_pid): break
	var rest := err.get_as_text()
	if rest != "": _line.call_deferred(rest.right(1500))
	_done.call_deferred()

func _line(l: String) -> void:
	_log.append_text(l + "\n")

func _done() -> void:
	if _thread: _thread.wait_to_finish(); _thread = null
	_pick.disabled = false
	_show_report(report())

func _restart() -> void:   # fresh start so Godot picks up the newly imported assets
	OS.create_process(OS.get_executable_path(), PackedStringArray(["--path", ProjectSettings.globalize_path("res://")]))
	get_tree().quit()

func _exit_tree() -> void:
	if _thread and _thread.is_started(): _thread.wait_to_finish()
