#!/usr/bin/env python3
"""Convert the approved artwork to desktop app icon formats (requires Pillow)."""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/jucier-icon-source.png"
MAC_ICONS = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
WINDOWS_ICON = ROOT / "windows/runner/resources/app_icon.ico"


def main() -> None:
    with Image.open(SOURCE) as source:
        artwork = source.convert("RGBA")
    if artwork.width != artwork.height:
        raise ValueError("The app icon source must be square")

    # The artwork already includes its rounded tile. Leave additional transparent
    # space around it to match macOS Dock icon proportions; do not mask it again.
    master = Image.new("RGBA", (1024, 1024))
    inset_artwork = artwork.resize((896, 896), Image.Resampling.LANCZOS)
    master.paste(inset_artwork, (64, 64))
    for size in (16, 32, 64, 128, 256, 512, 1024):
        icon = master.resize((size, size), Image.Resampling.LANCZOS)
        destination = MAC_ICONS / f"app_icon_{size}.png"
        icon.save(destination, optimize=True)
        print(destination.relative_to(ROOT))

    # ICO embeds each resolution so Explorer and taskbar icons stay sharp.
    artwork.save(
        WINDOWS_ICON,
        format="ICO",
        sizes=[(size, size) for size in (16, 20, 24, 32, 40, 48, 64, 128, 256)],
    )
    print(WINDOWS_ICON.relative_to(ROOT))


if __name__ == "__main__":
    main()
