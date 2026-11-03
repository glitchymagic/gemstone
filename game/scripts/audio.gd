class_name Audio
extends RefCounted
## Disc music (ADX -> MP3 by tools/adx_to_mp3.sh) with the disc's own loop start points.

static var _loops := {}

static func music(id: String) -> AudioStream:
	var path := "res://assets/audio/%s.mp3" % id
	if not ResourceLoader.exists(path): return null
	var s: AudioStreamMP3 = load(path)
	if _loops.is_empty() and FileAccess.file_exists("res://assets/audio/loops.json"):
		var j = JSON.parse_string(FileAccess.get_file_as_string("res://assets/audio/loops.json"))
		if j is Dictionary: _loops = j
	if _loops.has(id):
		s.loop = true
		s.loop_offset = float(_loops[id])
	return s

## The game's own announcer lines / sound effects (tools/sfx_extract.py: DTPK banks off the owner's disc -> assets/audio/se/)
static func se(id: String) -> AudioStream:
	var path := "res://assets/audio/se/%s.wav" % id
	return load(path) if ResourceLoader.exists(path) else null
