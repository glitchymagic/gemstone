#! p1=ryoma p2=falcon
# fx-cov: Londo's lamp post at (-428, 0, -256) (pole object kind 2, docs/COVERAGE.md). pole_wall started on the lower
# step and jumped over it 74 cm off. Here P1 starts ON the plaza level 100-150 cm north-east of the pole and runs DOWN
# (UP = 45 deg on this camera: o_pole_wall frame 24 facing 8192), 2 frames of run then a moving jump into the pole.
# Five tries, each from a fresh @place: DOWN k=100, DOWN k=150, DOWN+LEFT k=100, DOWN+RIGHT k=100, DOWN k=100 + X in the swing.
10
@place 1 -357 0 -185 40960
@place 2 300 0 300 49152
2 p1=DOWN
3 p1=DOWN+A
40 p1=DOWN
80
@place 1 -322 0 -150 40960
@place 2 300 0 300 49152
2 p1=DOWN
3 p1=DOWN+A
40 p1=DOWN
80
@place 1 -357 0 -185 40960
@place 2 300 0 300 49152
2 p1=DOWN+LEFT
3 p1=DOWN+LEFT+A
40 p1=DOWN+LEFT
80
@place 1 -357 0 -185 40960
@place 2 300 0 300 49152
2 p1=DOWN+RIGHT
3 p1=DOWN+RIGHT+A
40 p1=DOWN+RIGHT
80
@place 1 -357 0 -185 40960
@place 2 300 0 300 49152
2 p1=DOWN
3 p1=DOWN+A
12 p1=DOWN
4 p1=X
4
4 p1=Y
4
4 p1=A
80
