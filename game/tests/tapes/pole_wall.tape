#! p1=ryoma p2=falcon
# Londo lamp post (pole at -428, 0, -256). Near the south-west of the plaza the D-pad's UP runs at facing ~65 deg
# (move_basic), so P1 starts 220 cm before the pole on that line and runs UP into it, jumping at ~110 cm.
10
@place 1 -627 0 -349 11823
@place 2 300 0 300 49152
12 p1=UP
3 p1=UP+A
60 p1=UP
90
# the same, pressing B (action) in the air next to the pole
@place 1 -627 0 -349 11823
12 p1=UP
3 p1=UP+A
4 p1=UP
4 p1=UP+B
60
90
