#! p1=ryoma p2=falcon
# fx-item: items_weapon with the drop's category-0 list (1ST_READ 0x0C33CF00..02 = [0, 1, 2], read by the item pick
# 0x0C0CC72E; the second chest of a round is category 0) set to item 8 at frame 10, so the chest that appears at 599 at
# (430, 41, 0) holds item 8 (docs/ITEMS.md). P1 picks it up at 985, then X / Y aimed at P2 (as items_weapon).
10
@poke8 0x0C33CF00 8
@poke8 0x0C33CF01 8
@poke8 0x0C33CF02 8
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
