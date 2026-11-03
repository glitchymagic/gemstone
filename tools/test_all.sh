#!/bin/bash
# Headless suite (74 checks: rules, fighter, a plain match, then the same pair with cinematics on) + one full CPU-vs-CPU match per ripped fighter (vs the next one),
# Falcon vs Final Valgas, and one match on every stage.
# Usage: tools/test_all.sh      -> prints one TOTAL line per run; exit 1 if any run fails
cd "$(dirname "$0")/.."   # runs from its own checkout (master or a worktree)
G=/Applications/Godot.app/Contents/MacOS/Godot
L=${PS_TEST_LOGS:-/tmp/ps_tests_$(basename "$PWD")}; mkdir -p "$L"   # per-checkout logs: master and worktrees can run at once
ids=(falcon ryoma wangtang jack gunrock galuda ayame rouge kraken valgas)
have=()
for i in "${ids[@]}"; do f=$(grep -o "\"$i\", \"name\"[^}]*\"files\": \"P.." game/scripts/roster.gd | grep -o "P..$" | tr 'A-Z' 'a-z'); [ -f "game/assets/ripped/$f.glb" ] && have+=("$i"); done
rc=0
timeout 600 $G --headless --path game --fixed-fps 60 -s res://tests/run_tests.gd > $L/t_base.log 2>&1
echo "base: $(grep TOTAL $L/t_base.log)"; grep -q "0 failed" $L/t_base.log || rc=1
n=${#have[@]}
for ((k=0; k<n; k++)); do
  a=${have[$k]}; b=${have[$(( (k+1) % n ))]}
  PS_TEST_CHARS=$a,$b timeout 600 $G --headless --path game --fixed-fps 60 -s res://tests/run_tests.gd > $L/t_$a.log 2>&1
  echo "$a vs $b: $(grep TOTAL $L/t_$a.log)"; grep -q "0 failed" $L/t_$a.log || rc=1
done
if [ -f game/assets/ripped/pa0.glb ]; then   # the last boss (logged attack chains only, never walks)
  PS_TEST_CHARS=falcon,finalvalgas timeout 600 $G --headless --path game --fixed-fps 60 -s res://tests/run_tests.gd > $L/t_finalvalgas.log 2>&1
  echo "falcon vs finalvalgas: $(grep TOTAL $L/t_finalvalgas.log)"; grep -q "0 failed" $L/t_finalvalgas.log || rc=1
fi
for st in stg00 stg10 stg20 stg30 stg40 stg50 stg60 stg70 stg80 stg90 stga0; do   # one match on every stage
  [ -f game/assets/ripped/${st}_layout.json ] || continue
  PS_STAGE=$st PS_TEST_CHARS=falcon,ryoma timeout 600 $G --headless --path game --fixed-fps 60 -s res://tests/run_tests.gd > $L/t_$st.log 2>&1
  echo "falcon vs ryoma on $st: $(grep TOTAL $L/t_$st.log)"; grep -q "0 failed" $L/t_$st.log || rc=1
done
exit $rc
