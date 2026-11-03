#! p1=galuda p2=falcon
# fx-shot: every Power Drive / Fusion of moves_ from a fresh placement (tools/pc_shots.py tapes).
# A = P2 240 cm ahead, B = P2 farther + to the side, C = Fusion A+Y; full health before every press
10
# part A
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@gems 1 3
@hp 1 240
@hp 2 240
260
# X
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@hp 2 240
2
tap 1 p1=X
150
# Y
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@hp 2 240
2
tap 1 p1=Y
200
# AX
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@hp 2 240
2
3 p1=A
8
4 p1=X
150
# AY
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@hp 2 240
2
3 p1=A
8
4 p1=Y
200
# FX
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@hp 2 240
2
6 p1=A+X
450
# part B
@place 1 -180 0 -330 16384
@place 2 240 0 -180 49152
@gems 1 3
@hp 1 240
@hp 2 240
260
# X
@place 1 -180 0 -330 16384
@place 2 240 0 -180 49152
@hp 2 240
2
tap 1 p1=X
150
# Y
@place 1 -180 0 -330 16384
@place 2 240 0 -180 49152
@hp 2 240
2
tap 1 p1=Y
200
# AX
@place 1 -180 0 -330 16384
@place 2 240 0 -180 49152
@hp 2 240
2
3 p1=A
8
4 p1=X
150
# AY
@place 1 -180 0 -330 16384
@place 2 240 0 -180 49152
@hp 2 240
2
3 p1=A
8
4 p1=Y
200
# FX
@place 1 -180 0 -330 16384
@place 2 240 0 -180 49152
@hp 2 240
2
6 p1=A+X
450
# part C
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@gems 1 3
@hp 1 240
@hp 2 240
260
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@hp 2 240
2
6 p1=A+Y
600
