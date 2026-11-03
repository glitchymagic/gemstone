#! p1=kraken p2=falcon
# per-fighter move tape (tools/tapes.py expands {P1} {P2} -60 60 0 -330 -180): strings near and far, dash, air,
# grab, then Power Change by 3 gems with both Drives, air Drives and both Fusions. P2 stands still.
10
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 5 p1=X gap 8
150
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 4 p1=Y gap 8
150
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
tap 5 p1=X gap 8
120
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
tap 4 p1=Y gap 8
120
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
3 p1=A
4
4 p1=X
90
3 p1=A
12
4 p1=Y
90
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
4 p1=B
200
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@gems 1 3
260
tap 1 p1=X
150
tap 1 p1=Y
200
3 p1=A
8
4 p1=X
150
3 p1=A
8
4 p1=Y
200
6 p1=A+X
450
@place 1 -180 0 -330 16384
@place 2 60 0 -330 49152
@gems 1 3
260
6 p1=A+Y
600
