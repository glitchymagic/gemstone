#! p1=ryoma p2=falcon
# Londo raised floor at (250, 250, 700) cm (BUG-41: the remaster's CPU Falcon stood there 3,796 frames with the stick
# held toward the edge). P1 is put there four times and holds one direction each time: the disc walks / runs off the
# edge (state 14 = falling off a step) where the floor ends.
10
@place 1 250 250 700 0
@place 2 -300 0 -300 0
120 p1=UP
@place 1 250 250 700 16384
120 p1=RIGHT
@place 1 250 250 700 32768
120 p1=DOWN
@place 1 250 250 700 49152
120 p1=LEFT
60
