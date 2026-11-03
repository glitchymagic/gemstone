#! p1=falcon p2=ryoma
# fx-cov2, BUG-58 third probe: mash_s11's state 7 came 6 frames into a run that began out of state 24 (light-hit
# recovery). P1 (Falcon, Ryoma's stage) jabs P2 (Ryoma) once at 120 cm (Ryoma: k2/0 > 1 > 2 > state 24 8 rows),
# P2 holds DOWN+LEFT from 8 / 12 / 16 / 20 frames after the jab press, then DOWN+RIGHT (90 degrees) after 6 run frames.
10
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
10
4 p1=X
4
6 p2=DOWN+LEFT
30 p2=DOWN+RIGHT
50
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
10
4 p1=X
8
6 p2=DOWN+LEFT
30 p2=DOWN+RIGHT
50
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
10
4 p1=X
12
6 p2=DOWN+LEFT
30 p2=DOWN+RIGHT
50
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
10
4 p1=X
16
6 p2=DOWN+LEFT
30 p2=DOWN+RIGHT
50
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
10
4 p1=X
20
6 p2=DOWN+LEFT
30 p2=DOWN+RIGHT
50
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
10
4 p1=X
24
6 p2=DOWN+LEFT
30 p2=DOWN+RIGHT
50
