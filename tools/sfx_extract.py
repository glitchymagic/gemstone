#!/usr/bin/env python3
"""The game's own announcer lines (and later SFX) from the owner's disc into game/assets/audio/se/ (untracked, like the music).
NA.BIN is a DTPK bank (tools/dtpk.py) of the announcer; each line was identified by speech-to-text (whisper-cli,
ggml-base.en) on the decoded sample at 22,050 Hz, 2026-10-23:
  na_000 "Action!"  na_001 "Are you ready?"  na_006 "Time!"  na_012 "K.O.!"  na_018 "Perfect!"
(na_009 "Game over!", na_026 "Victory!", na_004 "Fantastic!", na_025 "Unbelievable!", na_029 "Wonderful!" unused yet)
Sound effects: which sample plays when was read off the sound chip in a real CPU-vs-CPU fight on Londo (tools/ref_londo.py
snd: the 64 AICA channels' start address / format / loop end / pitch every frame, banks placed in sound RAM): knockdown hits
key COMMON #28 (4-bit ADPCM, 22,050 Hz) on 18 of 27 hits plus the announcer's "Oh no!" (NA #16); the other hit and throw
impacts are 8-bit PCM samples the bank's sample table doesn't list (COMMON +0xC36E, +0x10588; 16,010 Hz, ~1 s).
Which of the game's impact samples each attack uses (its attack record) is not decoded: flinch hits use +0xC36E.
  sfx_extract.py"""
import os, shutil, sys, tempfile
sys.path.insert(0, os.path.dirname(__file__))
import dtpk

R = './'
OUT = R + 'game/assets/audio/se/'
PICK = {'NA': {0: 'vo_action', 1: 'vo_ready', 6: 'vo_time', 13: 'vo_ko', 16: 'vo_ohno', 18: 'vo_perfect'},   # KO call: #13 on the
        # disc in 10 of 10 logged KOs (fx-snd, docs/SOUND.md; #12 is another take)
        'COMMON': {28: 'se_hit_heavy'}}
RAW8 = {'se_hit': ('COMMON', 0xC36E, 16920, 16010), 'se_throw': ('COMMON', 0x10588, 16278, 16010)}   # offset, samples, Hz


def main():
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp(prefix='ps_sfx_')
    for bank, picks in PICK.items():
        dtpk.extract(R + f'rip/fs/{bank}.BIN', tmp + '/' + bank)
        for i, name in picks.items():
            src = f'{tmp}/{bank}/{bank.lower()}_{i:03d}.wav'
            shutil.move(src, OUT + name + '.wav')   # %TEMP% may be another drive (os.replace can't)
            print(bank, i, '->', name)
    import wave
    for name, (bank, ofs, n, hz) in RAW8.items():   # signed 8-bit PCM -> 16-bit WAV at the rate the game plays it
        raw = open(R + f'rip/fs/{bank}.BIN', 'rb').read()[ofs:ofs + n]
        pcm = b''.join(int.to_bytes(((b if b < 128 else b - 256) << 8) & 0xFFFF, 2, 'little') for b in raw)
        with wave.open(OUT + name + '.wav', 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(hz); w.writeframes(pcm)
        print(bank, hex(ofs), '->', name)


if __name__ == '__main__':
    main()
