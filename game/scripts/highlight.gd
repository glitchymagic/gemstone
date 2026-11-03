class_name Highlight
extends RefCounted
## Highlight clips: segments of recorded matches rendered offline by Godot's Movie Maker (a second Godot process:
## --write-movie <x.avi> --fixed-fps 60 at 1920x1080, main.gd --highlight <segments.json>), then ffmpeg makes an
## H.264 MP4 sized to post on X (yuv420p, +faststart, under 30 MB).

static func render_args(segments_json: String, avi: String, quality := 3) -> PackedStringArray:
	var a := PackedStringArray()
	if not OS.has_feature("template"): a.append_array(["--path", ProjectSettings.globalize_path("res://")])
	a.append_array(["--resolution", "1920x1080", "--write-movie", avi, "--fixed-fps", "60", "--",
		"--highlight", segments_json, "--quality", str(quality)])
	return a

static func ffmpeg() -> String:
	for p in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"]:
		if FileAccess.file_exists(p): return p
	var out := []
	if OS.execute("where" if OS.get_name() == "Windows" else "which", ["ffmpeg"], out) == 0 and out.size() > 0:
		var l := String(out[0]).strip_edges().split("\n")[0].strip_edges()
		if l != "": return l
	return ""

## Video bitrate that keeps `secs` of 1080p60 under ~28 MB with 160 kb/s AAC (capped at 9 Mb/s).
static func kbps_for(secs: float) -> int:
	return clampi(int(28.0 * 8192.0 / maxf(secs, 1.0)) - 200, 2500, 9000)

static func encode_args(avi: String, mp4: String, secs := 25.0) -> PackedStringArray:
	var k := kbps_for(secs)
	return PackedStringArray(["-y", "-loglevel", "error", "-i", avi, "-vf", "scale=in_range=pc:out_range=tv,format=yuv420p",
		"-c:v", "libx264", "-preset", "slow", "-profile:v", "high", "-b:v", "%dk" % k, "-maxrate", "%dk" % int(k * 1.2), "-bufsize", "%dk" % (k * 2),
		"-r", "60", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", mp4])
