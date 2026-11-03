#! p1=falcon p2=ryoma
# fx-shot: every Power Drive / Fusion of moves_ from a fresh placement (tools/pc_shots.py tapes).
# A = P2 240 cm ahead, B = P2 farther + to the side, C = Fusion A+Y; full health before every press
10
# part A
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@gems 1 3
@hp 1 240
@hp 2 240
260
# X
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@hp 2 240
2
tap 1 p1=X
150
# Y
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@hp 2 240
2
tap 1 p1=Y
200
# AX
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@hp 2 240
2
3 p1=A
8
4 p1=X
150
# AY
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@hp 2 240
2
3 p1=A
8
4 p1=Y
200
# FX
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@hp 2 240
2
6 p1=A+X
450
# part B
@place 1 -297 -30 -89 16384
@place 2 123 -30 61 49152
@gems 1 3
@hp 1 240
@hp 2 240
260
# X
@place 1 -297 -30 -89 16384
@place 2 123 -30 61 49152
@hp 2 240
2
tap 1 p1=X
150
# Y
@place 1 -297 -30 -89 16384
@place 2 123 -30 61 49152
@hp 2 240
2
tap 1 p1=Y
200
# AX
@place 1 -297 -30 -89 16384
@place 2 123 -30 61 49152
@hp 2 240
2
3 p1=A
8
4 p1=X
150
# AY
@place 1 -297 -30 -89 16384
@place 2 123 -30 61 49152
@hp 2 240
2
3 p1=A
8
4 p1=Y
200
# FX
@place 1 -297 -30 -89 16384
@place 2 123 -30 61 49152
@hp 2 240
2
6 p1=A+X
450
# part C
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@gems 1 3
@hp 1 240
@hp 2 240
260
@place 1 -297 -30 -89 16384
@place 2 -57 -30 -89 49152
@hp 2 240
2
6 p1=A+Y
600
