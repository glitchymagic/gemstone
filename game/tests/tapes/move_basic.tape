#! p1=ryoma p2=falcon
# from the fight-on frame: P1 taps punch every 12 frames, P2 taps RIGHT
tap 30 p1=X p2=RIGHT gap 8
# P1 runs in 8 directions (40 held + 30 free each), P2 idle
40 p1=UP
30
40 p1=UP+RIGHT
30
40 p1=RIGHT
30
40 p1=DOWN+RIGHT
30
40 p1=DOWN
30
40 p1=DOWN+LEFT
30
40 p1=LEFT
30
40 p1=UP+LEFT
30
# short taps: 1, 2, 3, 5, 8 frame presses of RIGHT
1 p1=RIGHT
30
2 p1=RIGHT
30
3 p1=RIGHT
30
5 p1=RIGHT
30
8 p1=RIGHT
30
# standing jump, moving jump, jump + direction mid-air, held jump
3 p1=A
60
20 p1=LEFT
3 p1=A+LEFT
50 p1=LEFT
30
3 p1=A
10
30 p1=RIGHT
30
40 p1=A
40
# turn-around: run right then instantly left
30 p1=RIGHT
30 p1=LEFT
30
