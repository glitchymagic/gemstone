#! p1=ryoma p2=falcon
# dash attacks (run then X / Y), jump attacks (jump then X / Y at 4 and 12 frames), action button (B) near P2 = grab/throw
10
@place 1 -300 0 -330 16384
@place 2 60 0 -330 49152
25 p1=RIGHT
4 p1=RIGHT+X
90
@place 1 -300 0 -330 16384
@place 2 60 0 -330 49152
25 p1=RIGHT
4 p1=RIGHT+Y
90
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
3 p1=A
4
4 p1=X
80
@place 1 -60 0 -330 16384
@place 2 60 0 -330 49152
3 p1=A
12
4 p1=Y
80
@place 1 -160 0 -330 16384
@place 2 60 0 -330 49152
10 p1=RIGHT
3 p1=RIGHT+A
6 p1=RIGHT
4 p1=RIGHT+X
80
@place 1 -40 0 -330 16384
@place 2 40 0 -330 49152
4 p1=B
150
@place 1 -40 0 -330 16384
@place 2 40 0 -330 49152
4 p2=B
150
