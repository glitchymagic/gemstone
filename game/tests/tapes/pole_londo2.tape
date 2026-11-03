#! p1=ryoma p2=falcon
# fx-cov: pole_londo bumped the lamp post (-428, 0, -256) at 60 cm and fell straight down in all 5 tries (jumps from
# 100-150 cm). Longer run-ups here: P1 300 cm north-east of the pole on the plaza, runs DOWN (= 225 deg, toward the
# pole) and jumps after 6 / 12 / 18 / 24 run frames (the pole reached high / mid / low in the jump), then a running
# jump held until it lands.
10
@place 1 -216 0 -44 40960
@place 2 300 0 300 49152
6 p1=DOWN
3 p1=DOWN+A
60 p1=DOWN
80
@place 1 -216 0 -44 40960
@place 2 300 0 300 49152
12 p1=DOWN
3 p1=DOWN+A
60 p1=DOWN
80
@place 1 -216 0 -44 40960
@place 2 300 0 300 49152
18 p1=DOWN
3 p1=DOWN+A
60 p1=DOWN
80
@place 1 -216 0 -44 40960
@place 2 300 0 300 49152
24 p1=DOWN
3 p1=DOWN+A
60 p1=DOWN
80
