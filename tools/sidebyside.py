#!/usr/bin/env python3
"""Side-by-side proof PNG: left = Flycast frame of the original disc, right = our render of the
ripped asset. Usage: sidebyside.py left.png right.png out.png "left label" "right label" """
import sys
from PIL import Image, ImageDraw, ImageFont
a, b = Image.open(sys.argv[1]).convert('RGB'), Image.open(sys.argv[2]).convert('RGB')
H = 720
a = a.resize((int(a.width * H / a.height), H), Image.LANCZOS)
b = b.resize((int(b.width * H / b.height), H), Image.LANCZOS)
out = Image.new('RGB', (a.width + b.width + 12, H + 56), (20, 20, 24))
out.paste(a, (0, 56)); out.paste(b, (a.width + 12, 56))
d = ImageDraw.Draw(out)
try: f = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 30)
except Exception: f = ImageFont.load_default()
d.text((14, 12), sys.argv[4] if len(sys.argv) > 4 else 'Flycast (disc)', fill=(255, 220, 90), font=f)
d.text((a.width + 26, 12), sys.argv[5] if len(sys.argv) > 5 else 'Ripped asset render', fill=(140, 220, 255), font=f)
out.save(sys.argv[3]); print('wrote', sys.argv[3], out.size)
