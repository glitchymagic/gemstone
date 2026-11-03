#! p1=ryoma p2=falcon
# fx-cov gems: drop on hit (how many, where they fly), pick-up, respawn. Original with the object pool logged
# (tools/covlog.py: gems = type 3 kind 5). P1 holds 2 gems, P2 1, both 100 cm apart in the middle of the start points.
10
@place 1 -164 0 -234 57344
@place 2 -234 0 -164 24576
@gems 1 2
@gems 2 1
30
# P2's punch string on P1 (P1 spills), then everything settles
tap 4 p2=X gap 10
300
# P1's kick string on P2 (P2 spills)
@place 1 -164 0 -234 57344
@place 2 -234 0 -164 24576
tap 3 p1=Y gap 12
300
# both run round the middle (touch-to-take any gem on the way)
40 p1=UP p2=DOWN
40 p1=RIGHT p2=LEFT
40 p1=DOWN p2=UP
40 p1=LEFT p2=RIGHT
40 p1=UP+RIGHT p2=DOWN+LEFT
40 p1=DOWN+LEFT p2=UP+RIGHT
# idle: gem respawn timing
900
