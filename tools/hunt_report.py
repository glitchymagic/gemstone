#!/usr/bin/env python3
"""Sum up a tools/hunt.sh run (BUG-28, docs/HUNT.md): counts per finding class (the lines to diff between two runs),
then every distinct finding with how many runs hit it and the first repro.
  tools/hunt_report.py OUT_DIR            -> summary on stdout, OUT_DIR/findings.json
  tools/hunt_report.py OUT_DIR OLD_DIR    -> also the per-class difference against an older run
Finding classes from game/tests/hunt.gd (godot_error, godot_warning, script_error, nan, hud_range, fell, oom,
stuck_state, softlock, anim_empty, pose_frozen, tpose, overlap, menu_stuck, sound_missing) plus, from the run logs:
hang (timeout), crash (no HUNT_END), exit_leak (Godot's leaked-objects lines at exit), log_error (any other ERROR /
WARNING line printed outside the harness's logger, e.g. before it was installed)."""
import json, os, re, sys, glob
from collections import defaultdict

GODOT_CMD = "Godot --headless --path game --fixed-fps 60 -s res://tests/hunt.gd --"


def norm(key):
    """A key without numbers that vary run to run (frames, positions), so one cause groups as one finding."""
    return re.sub(r"-?\d+(\.\d+)?", "#", key)


def load(out):
    runs, finds = [], []
    for jp in sorted(glob.glob(os.path.join(out, "*.jsonl"))):
        name = os.path.basename(jp)[:-6]
        rc_p = os.path.join(out, name + ".rc")
        log_p = os.path.join(out, name + ".log")
        if not os.path.exists(rc_p):
            continue   # still running
        rc = int(open(rc_p).read().strip() or 0)
        log = open(log_p, errors="replace").read() if os.path.exists(log_p) else ""
        summ = None
        rows = []
        for ln in open(jp, errors="replace"):
            ln = ln.strip()
            if not ln:
                continue
            try:
                d = json.loads(ln)
            except ValueError:
                continue
            if d.get("summary"):
                summ = d
            else:
                rows.append(d)
        run = {"name": name, "rc": rc, "summary": summ, "rows": rows}
        parts = name.split("_")
        run["look"], run["mode"] = parts[0], parts[1]
        extra = []
        if rc == 124:
            extra.append(("hang", "timeout (%s)" % name))
        elif "HUNT_END" not in log:
            extra.append(("crash", "no HUNT_END, exit %s (%s)" % (rc, name)))
        tail = log.split("HUNT_END", 1)[1] if "HUNT_END" in log else ""
        for m in re.finditer(r"^(WARNING|ERROR): (.*)$", tail, re.M):
            if "leaked at exit" in m.group(2) or "still in use at exit" in m.group(2):
                extra.append(("exit_leak", re.sub(r"\d+", "#", m.group(2))))
        head = log.split("HUNT_END", 1)[0]
        for m in re.finditer(r"^(SCRIPT ERROR|ERROR|WARNING): (.*)$", head, re.M):
            msg = m.group(2)
            if not any(msg[:60] in json.dumps(r.get("key", "")) for r in rows):
                extra.append(("log_error", "%s: %s" % (m.group(1), msg[:160])))
        for cls, key in extra:
            rows.append({"cls": cls, "key": key, "look": run["look"], "mode": run["mode"], "run": name, "ctx": {}})
        for r in rows:
            r.setdefault("run", name)
            cnt = 1
            if summ and r["cls"] + "|" + r["key"] in summ.get("counts", {}):
                cnt = summ["counts"][r["cls"] + "|" + r["key"]]
            r["count"] = cnt
        runs.append(run)
        finds.extend(rows)
    return runs, finds


def classes(finds):
    c = defaultdict(lambda: [0, set(), set()])
    for f in finds:
        c[f["cls"]][0] += f["count"]
        c[f["cls"]][1].add(f["run"])
        c[f["cls"]][2].add(norm(f["key"]))
    return c


def repro(f):
    if f.get("mode") in ("fight", "menus", "static") and "seed" in f:
        frames = f.get("ctx", {}).get("f", 0)
        st = f.get("stage", "-") if f["mode"] == "fight" else "-"
        ch = f.get("chars", "-") if f["mode"] == "fight" else "-"
        return "PS_LOOK=%s %s %s %s %s %s %d /tmp/h.jsonl   # at frame %s" % (
            f.get("look"), GODOT_CMD, f["mode"], st, ch, f["seed"], int(frames) + 60, frames)
    return f.get("run", "")


def main():
    out = sys.argv[1]
    runs, finds = load(out)
    frames = sum((r["summary"] or {}).get("frames", 0) for r in runs)
    matches = sum((r["summary"] or {}).get("matches", 0) for r in runs)
    looks = sorted({r["look"] for r in runs})
    cp = os.path.join(out, "commit.txt")
    commit = open(cp).read().split("\n")[0] if os.path.exists(cp) else "?"
    print("HUNT %s (code %s): %d runs (%s), %d frames (%.1f min of play), %d matches finished" % (
        os.path.basename(out.rstrip("/")), commit, len(runs), "/".join(looks), frames, frames / 3600.0, matches))
    cl = classes(finds)
    print("\nclass            occurrences  runs  distinct")
    for k in sorted(cl):
        print("%-16s %11d %5d %9d" % (k, cl[k][0], len(cl[k][1]), len(cl[k][2])))
    if len(sys.argv) > 2:
        _, old = load(sys.argv[2])
        oc = classes(old)
        print("\nvs %s (occurrences / distinct)" % sys.argv[2])
        for k in sorted(set(cl) | set(oc)):
            a = cl.get(k, [0, set(), set()]); b = oc.get(k, [0, set(), set()])
            print("%-16s %6d -> %-6d %4d -> %d" % (k, b[0], a[0], len(b[2]), len(a[2])))
    groups = defaultdict(list)
    for f in finds:
        groups[(f["cls"], norm(f["key"]))].append(f)
    rows = []
    for (cls, k), fs in groups.items():
        fs.sort(key=lambda x: (x.get("look", ""), x.get("run", "")))
        f0 = fs[0]
        rows.append({"cls": cls, "key": f0["key"], "group": k, "runs": len({x["run"] for x in fs}),
                     "count": sum(x["count"] for x in fs), "looks": sorted({x.get("look", "") for x in fs}),
                     "stages": sorted({x.get("stage", "") for x in fs if x.get("stage")}),
                     "chars": sorted({c for x in fs for c in str(x.get("chars", "")).split(",") if c and c != "-"}),
                     "repro": repro(f0), "ctx": f0.get("ctx", {})})
    rows.sort(key=lambda r: (-r["runs"], r["cls"]))
    json.dump(rows, open(os.path.join(out, "findings.json"), "w"), indent=1)
    print("\n%d distinct findings (findings.json); most runs first:" % len(rows))
    for r in rows[:60]:
        print("- [%s] %s  (runs %d, x%d, looks %s, stages %d, fighters %d)" % (
            r["cls"], r["key"][:150], r["runs"], r["count"], ",".join(r["looks"]), len(r["stages"]), len(r["chars"])))
        print("    repro: %s" % r["repro"])


if __name__ == "__main__":
    main()
