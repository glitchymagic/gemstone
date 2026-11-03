class_name TitleScreen
extends Node3D
## Title: the ripped Londo under the remaster lighting, slow orbit, title text, press start.

var cam: Camera3D
var t := 0.0
var music: AudioStreamPlayer
var ui: CanvasLayer
var blink: Label
var menu: VBoxContainer

func _ready() -> void:
	Look.build_environment(self)
	var a := Arena.new(); add_child(a); a.build(5)
	HD.stage(self, a)
	cam = Camera3D.new(); cam.fov = 50; cam.current = true; add_child(cam)
	ui = CanvasLayer.new(); add_child(ui)
	var v := VBoxContainer.new(); v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	ui.add_child(v)
	v.add_child(UI.label("POWER STONE", 150, Color(1.0, 0.82, 0.2)))
	v.add_child(UI.label("REMASTERED", 56, Color(0.9, 0.95, 1.0)))
	var sp := Control.new(); sp.custom_minimum_size = Vector2(0, 260); v.add_child(sp)
	blink = UI.label("PRESS START", 48)
	v.add_child(blink)
	# after START: the menu (arcade ladder, versus, picture quality, quit back to the desktop / Arcade launcher)
	menu = VBoxContainer.new(); menu.alignment = BoxContainer.ALIGNMENT_CENTER; menu.visible = false
	var ab := UI.button("ARCADE", func(): _go("arcade"))
	ab.disabled = Roster.load_ladder().is_empty()   # the ladder comes from the game itself (tools/ladder.py)
	menu.add_child(ab)
	menu.add_child(UI.button("VERSUS", func(): _go("versus")))
	menu.add_child(UI.button("TRAINING", func(): _go("training")))   # the game's hit spheres + frame data on screen
	menu.add_child(UI.button("BATTLE ROYALE", func(): UI.game().call("goto_brawl")))   # 2-4 fighters, the new mode
	menu.add_child(UI.button("REPLAYS", func(): UI.game().call("goto_replays", "")))   # every match is recorded
	var qb := UI.button("QUALITY: %s" % Look.PRESETS[int(UI.game().get("quality")) if UI.game() else 2], func(): pass)
	qb.pressed.connect(func():
		UI.game().set("quality", (int(UI.game().get("quality")) + 1) % Look.PRESETS.size())
		qb.text = "QUALITY: %s" % Look.PRESETS[int(UI.game().get("quality"))])
	menu.add_child(qb)
	var lb := UI.button("LOOK: %s" % str(UI.game().get("look") if UI.game() else "remaster").to_upper(), func(): pass)
	lb.pressed.connect(func():
		var i := HD.LOOKS.find(str(UI.game().get("look")))
		UI.game().set("look", HD.LOOKS[(i + 1) % HD.LOOKS.size()])
		lb.text = "LOOK: %s" % str(UI.game().get("look")).to_upper())
	menu.add_child(lb)
	var ib := UI.button("IMPACT FX: %s" % ("ON" if (UI.game() == null or UI.game().get("impact_fx")) else "OFF"), func(): pass)
	ib.pressed.connect(func():
		UI.game().set("impact_fx", not bool(UI.game().get("impact_fx")))
		ib.text = "IMPACT FX: %s" % ("ON" if UI.game().get("impact_fx") else "OFF"))
	menu.add_child(ib)
	var cb := UI.button("CINEMATICS: %s" % ("ON" if bool(UI.game().get("cinematics")) else "OFF (ORIGINAL)") if UI.game() else "CINEMATICS", func(): pass)
	cb.pressed.connect(func():   # Off = the original's presentation (fight camera, plain sparks)
		UI.game().set("cinematics", not bool(UI.game().get("cinematics")))
		cb.text = "CINEMATICS: %s" % ("ON" if bool(UI.game().get("cinematics")) else "OFF (ORIGINAL)"))
	menu.add_child(cb)
	var lgt := UI.button("LIGHTING: %s" % Remix.display(String(UI.game().get("lighting"))) if UI.game() else "LIGHTING", func(): pass)
	lgt.pressed.connect(func():   # Original (default) / Night / Sunset / Storm on every stage's own geometry
		var i := (Remix.LOOKS.find(String(UI.game().get("lighting"))) + 1) % Remix.LOOKS.size()
		UI.game().set("lighting", Remix.LOOKS[i])
		lgt.text = "LIGHTING: %s" % Remix.display(Remix.LOOKS[i]))
	menu.add_child(lgt)
	menu.add_child(UI.button("QUIT", func(): get_tree().quit()))
	for b in menu.get_children(): (b as Control).size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(menu)
	var hint := HintBar.new(); hint.items = [["cross", "Select"], ["circle", "Back"]]
	hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); hint.custom_minimum_size = Vector2(0, 60)
	hint.position.y = -70
	ui.add_child(hint)
	music = AudioStreamPlayer.new(); add_child(music)
	var s := Audio.music("OPEN")
	if s: music.stream = s; music.play()

var idle_t := 0.0
const ATTRACT_AFTER := 20.0   # seconds untouched on the title (menu closed) before the CPU-vs-CPU demo

func _process(dt: float) -> void:
	t += dt
	idle_t += dt
	if idle_t > ATTRACT_AFTER and not menu.visible and UI.game():
		idle_t = -999.0
		UI.game().call("start_attract")
		return
	cam.position = Vector3(sin(t * 0.1) * 9.0, 5.5, -11.0 + cos(t * 0.1) * 2.0)
	cam.look_at(Vector3(0, 1.5, 1.0), Vector3.UP)
	blink.modulate.a = 0.5 + 0.5 * sin(t * 4.0)

func _go(mode: String) -> void:
	UI.game().set("mode", mode)
	UI.game().call("goto_select")

func _unhandled_input(e: InputEvent) -> void:
	if e.is_pressed(): idle_t = 0.0
	if menu.visible:
		if (e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE) or \
			(e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B):
			menu.visible = false; blink.visible = true
		return
	if (e is InputEventKey and e.pressed and e.physical_keycode in [KEY_ENTER, KEY_SPACE, KEY_J]) or \
		(e is InputEventJoypadButton and e.pressed and e.button_index in [JOY_BUTTON_A, JOY_BUTTON_START]):
		blink.visible = false; menu.visible = true
		(menu.get_child(0) as Control).grab_focus()
		get_viewport().set_input_as_handled()
	elif (e is InputEventKey and e.pressed and e.physical_keycode == KEY_O) or \
		(e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_B):
		UI.game().set("quality", (int(UI.game().get("quality")) + 1) % Look.PRESETS.size())
		blink.text = "QUALITY: %s   (PRESS START)" % Look.PRESETS[int(UI.game().get("quality"))]
