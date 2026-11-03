#! p1=ryoma p2=falcon
# fx-cov: items_weapon with the second chest's item id set to 10 (+0x30C of pool slot 39 = 0x0C7D85D0, the chest that
# appears at frame 599 at (430, 41, 0) in this exact tape prefix) at frame 900, before it opens at 954. The remaster has
# no items (BUG-46): these tapes log what each item does on the disc (P1 picks it up at 985, X / Y aimed at P2).
10
890
@poke8 0x0C7D85D0 10
85
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
