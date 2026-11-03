#! p1=wangtang p2=falcon
# Power Change port check (fx-pc): 3 gems (@gems), the change, Drive X / Y, air Drives X / Y, Fusion A+X, again 3 gems
# + Fusion A+Y, then 3 gems and nothing pressed until the gauge runs out (2400 frames) and the revert. P2 stands far off.
10
@place 1 -180 0 -330 16384
@place 2 500 0 -330 49152
@gems 1 3
260
tap 1 p1=X
200
tap 1 p1=Y
250
3 p1=A
8
4 p1=X
200
3 p1=A
8
4 p1=Y
250
6 p1=A+X
600
@place 1 -180 0 -330 16384
@place 2 500 0 -330 49152
@gems 1 3
260
6 p1=A+Y
600
@place 1 -180 0 -330 16384
@place 2 500 0 -330 49152
@gems 1 3
2700
