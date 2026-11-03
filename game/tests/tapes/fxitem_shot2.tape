#! p1=ryoma p2=falcon
# fx-item: the shooter item 2 forced into the second chest (0x0C33CF00..02 = 2), picked up at 985, one X at 1081;
# the object pool (0x0C7D0980, 48 slots x 0x31C) is dumped every frame 1094-1113 to read the shot objects (type 5).
10
@poke8 0x0C33CF00 2
@poke8 0x0C33CF01 2
@poke8 0x0C33CF02 2
975
@place 1 320 0 0 16384
@place 2 20 0 0 16384
3 p1=B
60
3 p1=LEFT
30
4 p1=X
9
@dump shot2_1094.bin 0x0C7D0980 0x9540
@dump node2_1094.bin 0x0C36F000 0x2000
1
@dump shot2_1095.bin 0x0C7D0980 0x9540
@dump node2_1095.bin 0x0C36F000 0x2000
1
@dump shot2_1096.bin 0x0C7D0980 0x9540
@dump node2_1096.bin 0x0C36F000 0x2000
1
@dump shot2_1097.bin 0x0C7D0980 0x9540
@dump node2_1097.bin 0x0C36F000 0x2000
1
@dump shot2_1098.bin 0x0C7D0980 0x9540
@dump node2_1098.bin 0x0C36F000 0x2000
1
@dump shot2_1099.bin 0x0C7D0980 0x9540
@dump node2_1099.bin 0x0C36F000 0x2000
1
@dump shot2_1100.bin 0x0C7D0980 0x9540
@dump node2_1100.bin 0x0C36F000 0x2000
1
@dump shot2_1101.bin 0x0C7D0980 0x9540
@dump node2_1101.bin 0x0C36F000 0x2000
1
@dump shot2_1102.bin 0x0C7D0980 0x9540
@dump node2_1102.bin 0x0C36F000 0x2000
1
@dump shot2_1103.bin 0x0C7D0980 0x9540
@dump node2_1103.bin 0x0C36F000 0x2000
1
@dump shot2_1104.bin 0x0C7D0980 0x9540
@dump node2_1104.bin 0x0C36F000 0x2000
1
@dump shot2_1105.bin 0x0C7D0980 0x9540
@dump node2_1105.bin 0x0C36F000 0x2000
1
@dump shot2_1106.bin 0x0C7D0980 0x9540
@dump node2_1106.bin 0x0C36F000 0x2000
1
@dump shot2_1107.bin 0x0C7D0980 0x9540
@dump node2_1107.bin 0x0C36F000 0x2000
1
@dump shot2_1108.bin 0x0C7D0980 0x9540
@dump node2_1108.bin 0x0C36F000 0x2000
1
@dump shot2_1109.bin 0x0C7D0980 0x9540
@dump node2_1109.bin 0x0C36F000 0x2000
1
@dump shot2_1110.bin 0x0C7D0980 0x9540
@dump node2_1110.bin 0x0C36F000 0x2000
1
@dump shot2_1111.bin 0x0C7D0980 0x9540
@dump node2_1111.bin 0x0C36F000 0x2000
1
@dump shot2_1112.bin 0x0C7D0980 0x9540
@dump node2_1112.bin 0x0C36F000 0x2000
1
@dump shot2_1113.bin 0x0C7D0980 0x9540
@dump node2_1113.bin 0x0C36F000 0x2000
1
200
