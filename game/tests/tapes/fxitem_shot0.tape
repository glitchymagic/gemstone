#! p1=ryoma p2=falcon
# fx-item: the shooter item 0 forced into the second chest (0x0C33CF00..02 = 0), picked up at 985, one X at 1081;
# the object pool (0x0C7D0980, 48 slots x 0x31C) is dumped every frame 1094-1113 to read the shot objects (type 5).
10
@poke8 0x0C33CF00 0
@poke8 0x0C33CF01 0
@poke8 0x0C33CF02 0
975
@place 1 320 0 0 16384
@place 2 20 0 0 16384
3 p1=B
60
3 p1=LEFT
30
4 p1=X
9
@dump shot0_1094.bin 0x0C7D0980 0x9540
@dump node0_1094.bin 0x0C36F000 0x2000
1
@dump shot0_1095.bin 0x0C7D0980 0x9540
@dump node0_1095.bin 0x0C36F000 0x2000
1
@dump shot0_1096.bin 0x0C7D0980 0x9540
@dump node0_1096.bin 0x0C36F000 0x2000
1
@dump shot0_1097.bin 0x0C7D0980 0x9540
@dump node0_1097.bin 0x0C36F000 0x2000
1
@dump shot0_1098.bin 0x0C7D0980 0x9540
@dump node0_1098.bin 0x0C36F000 0x2000
1
@dump shot0_1099.bin 0x0C7D0980 0x9540
@dump node0_1099.bin 0x0C36F000 0x2000
1
@dump shot0_1100.bin 0x0C7D0980 0x9540
@dump node0_1100.bin 0x0C36F000 0x2000
1
@dump shot0_1101.bin 0x0C7D0980 0x9540
@dump node0_1101.bin 0x0C36F000 0x2000
1
@dump shot0_1102.bin 0x0C7D0980 0x9540
@dump node0_1102.bin 0x0C36F000 0x2000
1
@dump shot0_1103.bin 0x0C7D0980 0x9540
@dump node0_1103.bin 0x0C36F000 0x2000
1
@dump shot0_1104.bin 0x0C7D0980 0x9540
@dump node0_1104.bin 0x0C36F000 0x2000
1
@dump shot0_1105.bin 0x0C7D0980 0x9540
@dump node0_1105.bin 0x0C36F000 0x2000
1
@dump shot0_1106.bin 0x0C7D0980 0x9540
@dump node0_1106.bin 0x0C36F000 0x2000
1
@dump shot0_1107.bin 0x0C7D0980 0x9540
@dump node0_1107.bin 0x0C36F000 0x2000
1
@dump shot0_1108.bin 0x0C7D0980 0x9540
@dump node0_1108.bin 0x0C36F000 0x2000
1
@dump shot0_1109.bin 0x0C7D0980 0x9540
@dump node0_1109.bin 0x0C36F000 0x2000
1
@dump shot0_1110.bin 0x0C7D0980 0x9540
@dump node0_1110.bin 0x0C36F000 0x2000
1
@dump shot0_1111.bin 0x0C7D0980 0x9540
@dump node0_1111.bin 0x0C36F000 0x2000
1
@dump shot0_1112.bin 0x0C7D0980 0x9540
@dump node0_1112.bin 0x0C36F000 0x2000
1
@dump shot0_1113.bin 0x0C7D0980 0x9540
@dump node0_1113.bin 0x0C36F000 0x2000
1
200
