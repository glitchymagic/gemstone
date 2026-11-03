#! p1=ryoma p2=falcon
# ground strings at 120 cm, P2 standing still: punch string (tap X x5), kick string (tap Y x4), single punch, single kick
10
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 5 p1=X gap 8
120
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 4 p1=Y gap 8
120
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 1 p1=X
120
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 1 p1=Y
120
# slow taps (every 30 frames): which presses chain, which restart
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 4 p1=X gap 26
120
# out of reach (300 cm): whiff timing
@place 1 -150 0 -330 16384
@place 2 150 0 -330 49152
tap 3 p1=X gap 8
90
tap 2 p1=Y gap 8
90
# P2 attacks P1 (both sides)
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 3 p2=X gap 8
120
