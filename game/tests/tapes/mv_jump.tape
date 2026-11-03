#! p1=ryoma p2=falcon
# jumps: direction pressed mid-air (standing jump), released / reversed mid-air (moving jump), landing with
# direction held, jump from the stop state, jump held long, A tapped twice
10
@place 1 -60 0 -330 0
@place 2 300 0 300 49152
3 p1=A
6
30 p1=UP
40
@place 1 -60 0 -330 0
@place 2 300 0 300 49152
20 p1=UP
3 p1=UP+A
6 p1=UP
40
60
@place 1 -60 0 -330 0
@place 2 300 0 300 49152
20 p1=UP
3 p1=UP+A
6 p1=UP
20 p1=DOWN
60
@place 1 -60 0 -330 0
@place 2 300 0 300 49152
3 p1=A
50 p1=UP
40
@place 1 -60 0 -330 0
@place 2 300 0 300 49152
20 p1=UP
4
3 p1=A
70
@place 1 -60 0 -330 0
@place 2 300 0 300 49152
60 p1=A
60
@place 1 -60 0 -330 0
@place 2 300 0 300 49152
3 p1=A
10
3 p1=A
70
