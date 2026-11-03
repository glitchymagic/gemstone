#! p1=jack p2=falcon
# fx-cov2, BUG-58 (state 7 curved run k0/41): from standing facing +z (0) at (0, 0, 0) on Londo, each of the 8
# D-pad directions for 30 frames (the camera makes UP+LEFT ~ +z ahead, DOWN+RIGHT behind); then from a run
# ahead (UP+LEFT 20 frames) a switch to each direction for 30 frames. P2 parked far away. Which ones turn in an arc?
10
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=UP+LEFT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=UP
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=UP+RIGHT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=RIGHT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=DOWN+RIGHT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=DOWN
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=DOWN+LEFT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
30 p1=LEFT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
20 p1=UP+LEFT
30 p1=UP
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
20 p1=UP+LEFT
30 p1=UP+RIGHT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
20 p1=UP+LEFT
30 p1=RIGHT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
20 p1=UP+LEFT
30 p1=DOWN+RIGHT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
20 p1=UP+LEFT
30 p1=DOWN
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
20 p1=UP+LEFT
30 p1=DOWN+LEFT
40
@place 1 0 0 0 0
@place 2 -500 0 500 0
10
20 p1=UP+LEFT
30 p1=LEFT
40
