#! p1=ryoma p2=falcon
# fx-cov2, BUG-58 (state 7) second probe: turn_ryoma / turn_jack never entered state 7 (a 20-frame run then any
# switch = the facing jumps, the velocity swings over ~6 frames inside state 31). The disc's two cases: mash_s11 a
# 90-degree switch 6 frames into a run that began out of state 24; mash_s22 a direction held on the @place frame.
# Here: short runs (3 / 6 / 10 frames) then a 90 / 135 / 180-degree switch; then a direction held from the place frame.
10
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
3 p1=UP+LEFT
30 p1=UP+RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
3 p1=UP+LEFT
30 p1=RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
3 p1=UP+LEFT
30 p1=DOWN+RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
6 p1=UP+LEFT
30 p1=UP+RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
6 p1=UP+LEFT
30 p1=RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
6 p1=UP+LEFT
30 p1=DOWN+RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
10 p1=UP+LEFT
30 p1=UP+RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
10 p1=UP+LEFT
30 p1=RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
10
10 p1=UP+LEFT
30 p1=DOWN+RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
30 p1=UP
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
30 p1=RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
30 p1=DOWN+RIGHT
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
30 p1=DOWN
40
@place 1 -300 0 -300 0
@place 2 300 0 300 0
30 p1=LEFT
40
