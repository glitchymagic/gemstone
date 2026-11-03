class_name SelectScreen
extends Node3D
## Character select. Falcon and Ryoma are playable (ripped); the rest of the roster is listed
## as coming in a later pass. The highlighted fighter's real model turns on a plinth.

var idx := 1   # the game starts the cursor on slot 1 (Falcon; 0x0C7F2E54 = 1 when the screen opens)
var phase := 0       # 0 = P1 picking, 1 = P2 picking (only with a second pad)
var picks := []
var cam: Camera3D
var preview: Node3D
var ui: CanvasLayer
var grid: Control
var music: AudioStreamPlayer
var info: Label
var cool := 0.0

func _ready() -> void:
	Look.build_environment(self)
	cam = Camera3D.new(); cam.fov = 30; cam.current = true; add_child(cam)
	HD.light_rig(cam)
	cam.position = Vector3(0, 1.3, 5.2); cam.look_at(Vector3(0.9, 1.0, 0), Vector3.UP)
	HD.hero(self, cam, Vector3(-0.4, 1.0, 0.0))
	ui = CanvasLayer.new(); add_child(ui)
	var title := UI.label("SELECT YOUR FIGHTER", 64, Color(1, 0.85, 0.25))
	title.set_anchors_preset(Control.PRESET_TOP_WIDE); title.position.y = 30
	ui.add_child(title)
	grid = Control.new(); grid.set_anchors_preset(Control.PRESET_FULL_RECT)
	grid.draw.connect(_draw_grid); grid.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(grid)
	info = UI.label("", 34); info.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); info.position.y = -150
	ui.add_child(info)
	var hint := HintBar.new(); hint.items = [["cross", "Select"], ["circle", "Back"]]
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); hint.custom_minimum_size = Vector2(0, 60); hint.position.y = -70
	ui.add_child(hint)
	music = AudioStreamPlayer.new(); add_child(music)
	var s := Audio.music("P_SELE")
	if s: music.stream = s; music.play()
	_refresh()

func _refresh() -> void:
	if preview: preview.queue_free(); preview = null
	var c: Dictionary = Roster.selectable()[idx]
	if Roster.playable(c.id):
		preview = PSModel.create_for(c.id, false)
		if preview:
			add_child(preview)
			preview.position = Vector3(-0.4, 0, 0)
	var who := "P1" if phase == 0 else "P2"
	info.text = "%s: %s  -  home stage %s  -  Power Change: %s%s" % [who, c.name, c.stage, c.power,
		"" if Roster.playable(c.id) else "   (coming in a later pass)"]
	grid.queue_redraw()

func _process(dt: float) -> void:
	cool -= dt
	if preview: preview.rotation.y += dt * 0.8

func _draw_grid() -> void:
	var font := ThemeDB.fallback_font
	var vs := grid.size
	for i in Roster.selectable().size():
		var c: Dictionary = Roster.selectable()[i]
		var col := i % 5; var row := i / 5
		var r := Rect2(vs.x * 0.5 + 20 + col * 150, 190 + row * 230, 140, 220)
		var ok := Roster.playable(c.id)
		grid.draw_rect(r, Color(0.15, 0.12, 0.2, 0.85) if ok else Color(0.08, 0.08, 0.1, 0.7))
		var fc := Roster.face(c.id)
		if not fc.is_empty():   # the original portrait + name banner from the disc
			grid.draw_texture_rect_region(fc[0], Rect2(r.position + Vector2(4, 4), Vector2(132, 212)), fc[1], Color.WHITE if ok else Color(0.35, 0.35, 0.4))
		else:
			grid.draw_string(font, r.position + Vector2(10, 40), c.name, HORIZONTAL_ALIGNMENT_LEFT, 130, 22, Color.WHITE if ok else Color(0.5, 0.5, 0.55))
		if i == idx: grid.draw_rect(r.grow(4), Color(1, 0.8, 0.2), false, 4)
		if not ok: grid.draw_string(font, r.position + Vector2(8, 205), "not ripped yet", HORIZONTAL_ALIGNMENT_LEFT, 130, 16, Color(0.9, 0.8, 0.5))

func _unhandled_input(e: InputEvent) -> void:
	var dx := 0
	if e is InputEventKey and e.pressed and not e.echo:
		match e.physical_keycode:
			KEY_A, KEY_LEFT: dx = -1
			KEY_D, KEY_RIGHT: dx = 1
			KEY_W, KEY_UP: dx = -5
			KEY_S, KEY_DOWN: dx = 5
			KEY_ENTER, KEY_SPACE, KEY_J: _confirm()
			KEY_ESCAPE, KEY_L: UI.game().call("goto_title")
	elif e is InputEventJoypadButton and e.pressed:
		match e.button_index:
			JOY_BUTTON_DPAD_LEFT: dx = -1
			JOY_BUTTON_DPAD_RIGHT: dx = 1
			JOY_BUTTON_DPAD_UP: dx = -5
			JOY_BUTTON_DPAD_DOWN: dx = 5
			JOY_BUTTON_A: _confirm()
			JOY_BUTTON_B: UI.game().call("goto_title")
	elif e is InputEventJoypadMotion and abs(e.axis_value) > 0.6 and cool <= 0.0:
		cool = 0.25
		if e.axis == JOY_AXIS_LEFT_X: dx = 1 if e.axis_value > 0 else -1
		elif e.axis == JOY_AXIS_LEFT_Y: dx = 5 if e.axis_value > 0 else -5
	if dx != 0:
		idx = posmod(idx + dx, Roster.selectable().size())
		_refresh()

func _confirm() -> void:
	var c: Dictionary = Roster.selectable()[idx]
	if not Roster.playable(c.id): return
	picks.append(c.id)
	if UI.game().get("mode") == "arcade":
		UI.game().call("start_arcade", c.id); return
	var two_pads := Input.get_connected_joypads().size() >= 2
	if phase == 0 and two_pads:
		phase = 1; _refresh(); return
	if picks.size() == 1:   # one pad: the CPU takes the next playable fighter (arcade mode has the real ladder)
		var i0 := idx
		for k in range(1, Roster.selectable().size()):
			var o: Dictionary = Roster.selectable()[(i0 + k) % Roster.selectable().size()]
			if Roster.playable(o.id): picks.append(o.id); break
		if picks.size() == 1: picks.append(picks[0])
	UI.game().set("chars", picks)
	UI.game().set("cpu", [false, not two_pads])
	UI.game().call("start_fight")
