# Jucier application icon

`jucier-icon-source.png` is the approved original artwork, generated with the
built-in ImageGen tool. It depicts a matte milk-white manual citrus press
squeezing a folded-corner document into orange juice, with a satin-silver lever
and a warm orange/apricot macOS rounded-square tile. The area outside the tile
is transparent.

Regenerate the macOS asset catalog PNGs and the Windows multi-resolution ICO
with Python and Pillow:

```sh
python3 tool/generate_app_icons.py
```

macOS outputs are 16, 32, 64, 128, 256, 512, and 1024 pixels. Their transparent
padding matches the visual scale of native Dock icons. Windows includes 16,
20, 24, 32, 40, 48, 64, 128, and 256 pixel frames.

The complete generation prompt is saved in `icon-prompt.txt`.
