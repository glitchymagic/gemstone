extends RefCounted
## Attract mode + menus, headless: cinematics default Off (the original's presentation); the title left alone starts a
## CPU-vs-CPU demo that follows the CINEMATICS setting (Off: none, On: cinematics); any button returns to the title; the
## title menu has every new entry.

var t: SceneTree
var g: Node
var n := 0
var finished := false

func _init(runner: SceneTree) -> void:
	t = runner

func check(c: bool, what: String) -> void:
	t.call("check", c, what)

func tick() -> void:
	n += 1
	match n:
		1:
			print("== attract mode + menus")
			g = t.root.get_node_or_null("Game")   # the autoload (present in -s runs too)
			if g == null:
				g = load("res://scripts/game.gd").new(); g.name = "Game"; t.root.add_child(g)
			g.call("goto_title")
		4:
			var ts = g.get("current")
			check(ts is TitleScreen, "title screen up")
			var labels := []
			for b in (ts as TitleScreen).menu.get_children(): labels.append((b as Button).text.get_slice(":", 0))
			for want in ["ARCADE", "VERSUS", "TRAINING", "BATTLE ROYALE", "REPLAYS", "CINEMATICS", "LIGHTING", "QUIT"]:
				check(want in labels, "title menu has %s" % want)
			var fresh: Node = load("res://scripts/game.gd").new()
			check(fresh.get("cinematics") == false and g.get("cinematics") == false, "cinematics default Off (the original's presentation)")
			fresh.free()
			var cb := ""
			for b in (ts as TitleScreen).menu.get_children(): if (b as Button).text.begins_with("CINEMATICS"): cb = (b as Button).text
			check(cb == "CINEMATICS: OFF (ORIGINAL)", "title menu shows CINEMATICS: OFF (ORIGINAL) (%s)" % cb)
			(ts as TitleScreen).idle_t = TitleScreen.ATTRACT_AFTER - 0.01
		8:
			var f = g.get("current")
			check(f is Fight and (f as Fight).attract and (f as Fight).cinema == null and (f as Fight).cpu_flags.all(func(c): return c), "idle title -> CPU-vs-CPU demo, no cinematics by default")
		60:
			var ev := InputEventKey.new(); ev.pressed = true; ev.physical_keycode = KEY_SPACE
			(g.get("current") as Fight)._unhandled_input(ev)
		64:
			check(g.get("current") is TitleScreen and String(g.get("lighting")) == "original", "any button: back to the title, original look")
			g.set("cinematics", true)   # the menu option: the demo follows it
			g.call("start_attract")
		68:
			var f = g.get("current")
			check(f is Fight and (f as Fight).attract and (f as Fight).cinema != null, "CINEMATICS ON: the demo plays with cinematics")
			g.set("cinematics", false); g.set("lighting", "original"); g.set("mode", "versus")
			var c = g.get("current")
			if c: c.queue_free()
			g.set("current", null)
			finished = true
