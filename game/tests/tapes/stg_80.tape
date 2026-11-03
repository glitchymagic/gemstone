#! p1=wangtang p2=kraken
# fx-cov stage tape stg80 (tools/cov_tapes.py): walls / edges / ledges / wall kicks,
# jumps, close-range attacks. Every block starts from the same @place (the start points) on both sides.
10
# run UP into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=UP p2=DOWN
3 p1=UP+A p2=DOWN+A
12 p1=UP p2=DOWN
3 p1=UP+A p2=DOWN+A
12 p1=UP p2=DOWN
3 p1=UP+A p2=DOWN+A
20 p1=UP p2=DOWN
25
# run RIGHT into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=RIGHT p2=LEFT
3 p1=RIGHT+A p2=LEFT+A
12 p1=RIGHT p2=LEFT
3 p1=RIGHT+A p2=LEFT+A
12 p1=RIGHT p2=LEFT
3 p1=RIGHT+A p2=LEFT+A
20 p1=RIGHT p2=LEFT
25
# run DOWN into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=DOWN p2=UP
3 p1=DOWN+A p2=UP+A
12 p1=DOWN p2=UP
3 p1=DOWN+A p2=UP+A
12 p1=DOWN p2=UP
3 p1=DOWN+A p2=UP+A
20 p1=DOWN p2=UP
25
# run LEFT into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=LEFT p2=RIGHT
3 p1=LEFT+A p2=RIGHT+A
12 p1=LEFT p2=RIGHT
3 p1=LEFT+A p2=RIGHT+A
12 p1=LEFT p2=RIGHT
3 p1=LEFT+A p2=RIGHT+A
20 p1=LEFT p2=RIGHT
25
# run UP+RIGHT into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=UP+RIGHT p2=DOWN+LEFT
3 p1=UP+RIGHT+A p2=DOWN+LEFT+A
12 p1=UP+RIGHT p2=DOWN+LEFT
3 p1=UP+RIGHT+A p2=DOWN+LEFT+A
12 p1=UP+RIGHT p2=DOWN+LEFT
3 p1=UP+RIGHT+A p2=DOWN+LEFT+A
20 p1=UP+RIGHT p2=DOWN+LEFT
25
# run DOWN+RIGHT into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=DOWN+RIGHT p2=UP+LEFT
3 p1=DOWN+RIGHT+A p2=UP+LEFT+A
12 p1=DOWN+RIGHT p2=UP+LEFT
3 p1=DOWN+RIGHT+A p2=UP+LEFT+A
12 p1=DOWN+RIGHT p2=UP+LEFT
3 p1=DOWN+RIGHT+A p2=UP+LEFT+A
20 p1=DOWN+RIGHT p2=UP+LEFT
25
# run DOWN+LEFT into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=DOWN+LEFT p2=UP+RIGHT
3 p1=DOWN+LEFT+A p2=UP+RIGHT+A
12 p1=DOWN+LEFT p2=UP+RIGHT
3 p1=DOWN+LEFT+A p2=UP+RIGHT+A
12 p1=DOWN+LEFT p2=UP+RIGHT
3 p1=DOWN+LEFT+A p2=UP+RIGHT+A
20 p1=DOWN+LEFT p2=UP+RIGHT
25
# run UP+LEFT into the wall / edge, then 3 jump presses there (wall kick / ledge)
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
90 p1=UP+LEFT p2=DOWN+RIGHT
3 p1=UP+LEFT+A p2=DOWN+RIGHT+A
12 p1=UP+LEFT p2=DOWN+RIGHT
3 p1=UP+LEFT+A p2=DOWN+RIGHT+A
12 p1=UP+LEFT p2=DOWN+RIGHT
3 p1=UP+LEFT+A p2=DOWN+RIGHT+A
20 p1=UP+LEFT p2=DOWN+RIGHT
25
# running jump UP
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
15 p1=UP p2=DOWN
3 p1=UP+A p2=DOWN+A
45 p1=UP p2=DOWN
25
# running jump RIGHT
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
15 p1=RIGHT p2=LEFT
3 p1=RIGHT+A p2=LEFT+A
45 p1=RIGHT p2=LEFT
25
# running jump LEFT
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
15 p1=LEFT p2=RIGHT
3 p1=LEFT+A p2=RIGHT+A
45 p1=LEFT p2=RIGHT
25
# standing jumps
@place 1 5 0 -445 57344
@place 2 -277 0 -163 24576
3 p1=A p2=A
60
# 100 cm apart in the middle: punch string, kick string, both, grab
@place 1 -101 0 -339 57344
@place 2 -171 0 -269 24576
tap 4 p1=X gap 10
60
tap 3 p2=Y gap 12
90
tap 3 p1=Y p2=X gap 9
90
@place 1 -101 0 -339 57344
@place 2 -171 0 -269 24576
3 p1=B
120
3 p2=B
150
