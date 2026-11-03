#! p1=ryoma p2=falcon
# Londo throwables: the metal chair (part 32 at -469, 25, 5): P1 walks into it and presses B (pick up), throws it (X)
# at P2; then the potted plant (part 53 at -645, 0, 456): pick up + kick (Y) = swing?; then B again = drop?
10
@place 1 -380 0 5 49152
@place 2 -100 0 5 49152
20
4 p1=B
60
4 p1=X
90
@place 1 -560 0 456 49152
@place 2 -300 0 456 49152
20
4 p1=B
60
4 p1=Y
90
4 p1=B
60
