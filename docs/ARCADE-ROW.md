# Power Stone arcade ladder row: how the game picks it

**Rule:** it's random, and it doesn't depend on the fighter. The row is rolled once per player when the character-select screen opens, before you pick anyone:
`row = (u32)(frand() * 255.0) % 8`, where `frand() = rand() / 32768`.
`rand()` is the standard C LCG: `s = s*1103515245 + 12345; return (s>>16) & 0x7FFF`.

**Code (1ST_READ, 0x8C... = 0x0C...)**
- Select-screen per-player init: 0x0C0A4724. It is called with the player struct (P1 0x0C7E40C4 / P2 0x0C7EB394) when the select state byte (block+90) is 0.
- The roll is at 0x0C0A4816-0x0C0A4850. It calls frand at 0x0C0DF940, multiplies by 255.0f (0x0C0A48BC), takes the remainder with `__modlu` at 0x0C0E6F24 (r0 = 8), and stores the result at block+85.
- rand() is at 0x0C0DF920. srand() (0x0C0DF960) is never called: no bsr/jsr literal and no pointer to it anywhere in the binary.
- The roll is skipped, and the cursor goes back to your current fighter, when `byte 0x0C7F3074 & (player+1)` is set or block+76 != 0. After every fight, 0x0C053D5C copies the joined-players mask into 0x0C7F3074. So a continue keeps the row.
- Only the roll writes the row. Code at 0x0C0A43D6, 0x0C0A5680, 0x0C0A8FFE and 0x0C0A9E4A reads it.

**RAM**
- Per-player block base: 0x0C7F2DF0 + 120*p.
  - +85 = row (0x0C7F2E45)
  - +86 = fight
  - +90 = select state
  - +100 = cursor (0x0C7F2E54)
- RNG state: u32 at 0x0C346A50. Its initial value in the file is 1.

**Seed / time:** there is no seed, and no frame counter or clock feeds it. The state starts at 1 at boot and only moves when something calls rand() (CPU AI, effects, the attract-demo fights). From power-on everything is deterministic: two separate attract recordings pass through identical states (demo_01 = attb_02, demo_02 = attb_07, demo_06 = attb_23). In practice the row depends on how much of the attract loop ran before Start.

**Rows 8 and 9:** the roll can't reach them (`% 8`), and nothing else writes the row. They look like unused placeholders: they repeat row 7's tail with a different first entry. Kraken (fk) and Valgas (fv) players got normal rows, 2 and 1.

**Distribution:** close to even. Rows 0-6 each come up about 12.5% of the time; row 7 is about 3% rarer (3999 of 32768 rand values).

**Check (confidence: high)**
I brute-forced how many rand() calls each dump's RNG state is from boot.
- sel0-3 (on the select screen, 10605 calls): the row stored is 6, and the formula gives 6.
- selk0-1 (10704 calls): the row stored is 4, and the formula gives 4.

Both select-screen dumps match exactly; two chance matches would be 1 in 64. Every arcade dump has a row in 0-7. ladC_00 and ladD_00 have the same RNG state and the same row (1). I couldn't check fight dumps directly, because the RNG keeps moving after the pick.

```python
def pick_row(s):  # s = u32 at 0x0C346A50 just before the select screen opens
    s = (s * 1103515245 + 12345) & 0xFFFFFFFF
    return (((s >> 16) & 0x7FFF) * 255 >> 15) % 8, s   # (row, new state)
# On a select-screen dump, the stored state is already past the roll:
# row == (((s >> 16) & 0x7FFF) * 255 >> 15) % 8
```

Scripts: /tmp/ps4_row.py, /tmp/ps4_lcg.c (calls since boot), /tmp/ps4_steps.txt (calls since boot per dump).
