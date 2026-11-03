#! p1=ryoma p2=falcon
# fx-cov2, BUG-65 (world freeze): P1 Power Changes at frame 11 (forced 3 gems); P2 runs then punches DURING the 130-frame
# transform (the disc: P2 frozen?), the floor gem's frame-299 drop (shifted by the freeze?), then P1's Fusion (A+X) at 200
# with P2 running through its flash. Logged: round clock, both recovery counters (+0x720F, .bin), the object pool.
10
@place 1 -100 0 -330 16384
@place 2 150 0 -330 49152
@gems 1 3
20
60 p2=UP
4 p2=X
106
6 p1=A+X
20
70 p2=DOWN
520
