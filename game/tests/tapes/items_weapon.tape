#! p1=ryoma p2=falcon
# fx-cov: an item from the stage's item chest (docs/COVERAGE.md "Items"). On Londo the original's second chest
# appears at frame 599 at (430, 41, 0), opens into an item (type 3 kind 6) at 954, ready (sub 0) at 977. P1 is placed
# 110 cm west of it facing it, P2 300 cm further west; P1 presses B (pick up) at 985, then X / Y (use) aimed at P2.
10
975
@place 1 320 0 0 16384
@place 2 20 0 0 16384
3 p1=B
60
3 p1=LEFT
30
tap 3 p1=X gap 40
60
tap 3 p1=Y gap 40
240
