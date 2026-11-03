#! p1=jack p2=wangtang
# fx-cov2, BUG-63 (ledge hang state 36 k2/207 > hang attack k1/162): the disc hung Wang-Tang on a wall top in
# mash_s22 at f482 right after X+Y+DOWN (= B, the action button) came at f480 in a moving jump against the wall
# (z 572.7, y 408.9). First version (no B) only slid up the wall: B in the air at a wall top is the catch.
# From (-439, 100, 502): a running jump (UP+LEFT, then LEFT: the two directions that meet the wall), B pressed
# 4 / 8 / 12 / 16 frames into the jump, then UP+Y (the hang attack) 22 frames later.
10
@place 2 -439 100 502 24576
20
4 p2=UP+LEFT
6 p2=UP+LEFT+A
6 p2=B
16
6 p2=UP+Y
60
@place 2 -439 100 502 24576
20
4 p2=UP+LEFT
6 p2=UP+LEFT+A
2 p2=UP+LEFT
6 p2=B
16
6 p2=UP+Y
60
@place 2 -439 100 502 24576
20
4 p2=UP+LEFT
6 p2=UP+LEFT+A
6 p2=UP+LEFT
6 p2=B
16
6 p2=UP+Y
60
@place 2 -439 100 502 24576
20
4 p2=UP+LEFT
6 p2=UP+LEFT+A
10 p2=UP+LEFT
6 p2=B
16
6 p2=UP+Y
60
@place 2 -439 100 502 24576
20
4 p2=LEFT
6 p2=LEFT+A
6 p2=B
16
6 p2=UP+Y
60
@place 2 -439 100 502 24576
20
4 p2=LEFT
6 p2=LEFT+A
2 p2=LEFT
6 p2=B
16
6 p2=UP+Y
60
@place 2 -439 100 502 24576
20
4 p2=LEFT
6 p2=LEFT+A
6 p2=LEFT
6 p2=B
16
6 p2=UP+Y
60
@place 2 -439 100 502 24576
20
4 p2=LEFT
6 p2=LEFT+A
10 p2=LEFT
6 p2=B
16
6 p2=UP+Y
60
