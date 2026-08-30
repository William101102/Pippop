#!/usr/bin/env python3
"""
Builds the iOS app icon and splash screen from the source artwork.

Usage: python3 ios-setup/generate-icons.py

Two things make the source art unusable as-is on iOS:

  * It has an alpha channel, and App Store Connect rejects icons with one.
  * Its corners are already rounded, more tightly than iOS's own mask. iOS
    applies that mask regardless, so shipping pre-rounded art leaves the
    flattened background peeking out around the mask.

So the art is cropped inward until the corners are opaque, then scaled to the
exact size Apple wants and flattened. Requires Pillow: pip3 install Pillow
"""
from pathlib import Path
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: pip3 install Pillow")

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "public" / "icons" / "pinpop-app-icon.png"
OUT_DIR = ROOT / "ios-setup" / "assets"

# Matches --coral in styles.css, so any residual edge blends with the art.
BACKDROP = (255, 248, 239)
ICON_PX = 1024
# Capacitor scales one square down for every launch-screen size.
SPLASH_PX = 2732
SPLASH_LOGO_FRACTION = 0.32


def opaque_crop(image: Image.Image) -> Image.Image:
    """Crops in from the edges until all four corners are fully opaque."""
    alpha = image.split()[3]
    width, height = image.size
    pixels = alpha.load()

    inset = 0
    limit = min(width, height) // 4
    while inset < limit:
        corners = [
            pixels[inset, inset],
            pixels[width - 1 - inset, inset],
            pixels[inset, height - 1 - inset],
            pixels[width - 1 - inset, height - 1 - inset],
        ]
        if all(value >= 250 for value in corners):
            break
        inset += 2

    if inset >= limit:
        raise SystemExit("Could not find an opaque crop; is the source art square?")

    print(f"  cropped {inset}px per side so the corners are opaque")
    return image.crop((inset, inset, width - inset, height - inset))


def main() -> None:
    if not SOURCE.exists():
        raise SystemExit(f"Source art not found: {SOURCE}")

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    art = Image.open(SOURCE).convert("RGBA")
    print(f"source {SOURCE.name} {art.size[0]}x{art.size[1]}")

    # App icon: full bleed, no alpha, exactly 1024.
    cropped = opaque_crop(art)
    icon = Image.new("RGB", cropped.size, BACKDROP)
    icon.paste(cropped, (0, 0), cropped)
    icon = icon.resize((ICON_PX, ICON_PX), Image.LANCZOS)
    icon_path = OUT_DIR / "AppIcon-1024.png"
    icon.save(icon_path, "PNG")
    print(f"  wrote {icon_path.relative_to(ROOT)} {ICON_PX}x{ICON_PX} (no alpha)")

    # Splash: the rounded art centred on the app background, so the launch
    # screen matches the first painted frame instead of flashing white.
    splash = Image.new("RGB", (SPLASH_PX, SPLASH_PX), BACKDROP)
    logo_px = int(SPLASH_PX * SPLASH_LOGO_FRACTION)
    logo = art.resize((logo_px, logo_px), Image.LANCZOS)
    offset = (SPLASH_PX - logo_px) // 2
    splash.paste(logo, (offset, offset), logo)
    splash_path = OUT_DIR / "splash-2732.png"
    splash.save(splash_path, "PNG")
    print(f"  wrote {splash_path.relative_to(ROOT)} {SPLASH_PX}x{SPLASH_PX}")

    # Web and PWA keep the alpha and the original rounding; only the sizes change.
    for size in (64, 192, 512):
        name = "favicon-64.png" if size == 64 else f"icon-{size}.png"
        art.resize((size, size), Image.LANCZOS).save(ROOT / "public" / "icons" / name, "PNG")
        print(f"  refreshed public/icons/{name}")


if __name__ == "__main__":
    main()
