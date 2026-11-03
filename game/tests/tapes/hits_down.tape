#! p1=ryoma p2=falcon
# knockdown + get-up: P1 full punch string on P2, P2 mashes nothing, then P2 mashes A during the get-up; then a KO
10
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 5 p1=X gap 8
200
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
tap 5 p1=X gap 8
40
tap 15 p2=A gap 4
100
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
@hp 2 5
tap 1 p1=X
600
