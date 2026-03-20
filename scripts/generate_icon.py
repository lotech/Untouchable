#!/usr/bin/env python3
"""Generate Untouchable app icon PNGs from SVG at all required macOS sizes."""

import cairosvg
import os

# Icon concept: A touch/tap point (concentric circles radiating from a finger dot)
# with a prohibition circle-slash over it, on a rich indigo-to-blue gradient.
# Clean, bold, simple -- works at 16px and 1024px. Follows macOS 26 guidelines:
# high contrast, no text, clear silhouette, bold shapes for Liquid Glass.

SVG_ICON = r"""<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <defs>
    <!-- Background gradient: deep indigo to vibrant blue -->
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#4A00E0"/>
      <stop offset="100%" stop-color="#1E90FF"/>
    </linearGradient>

    <!-- Subtle inner glow for depth -->
    <radialGradient id="glow" cx="0.4" cy="0.35" r="0.65">
      <stop offset="0%" stop-color="rgba(255,255,255,0.15)"/>
      <stop offset="100%" stop-color="rgba(255,255,255,0)"/>
    </radialGradient>

    <!-- Prohibition slash gradient for subtle 3D feel -->
    <linearGradient id="slashGrad" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#FF4060"/>
      <stop offset="100%" stop-color="#FF2040"/>
    </linearGradient>
  </defs>

  <!-- macOS rounded-rect (squircle) background -->
  <rect x="0" y="0" width="1024" height="1024" rx="228" ry="228" fill="url(#bg)"/>

  <!-- Inner glow overlay -->
  <rect x="0" y="0" width="1024" height="1024" rx="228" ry="228" fill="url(#glow)"/>

  <!-- Touch point: center dot -->
  <circle cx="512" cy="480" r="52" fill="white" opacity="0.95"/>

  <!-- Touch ripple rings (concentric, fading outward) -->
  <circle cx="512" cy="480" r="120" fill="none" stroke="white" stroke-width="24" opacity="0.7"/>
  <circle cx="512" cy="480" r="200" fill="none" stroke="white" stroke-width="20" opacity="0.45"/>
  <circle cx="512" cy="480" r="280" fill="none" stroke="white" stroke-width="16" opacity="0.25"/>

  <!-- Prohibition circle -->
  <circle cx="512" cy="512" r="340" fill="none" stroke="url(#slashGrad)" stroke-width="52" opacity="0.92"/>

  <!-- Prohibition slash (diagonal line from top-right to bottom-left) -->
  <line x1="752" y1="272" x2="272" y2="752"
        stroke="url(#slashGrad)" stroke-width="52" stroke-linecap="round" opacity="0.92"/>
</svg>
"""

# macOS icon sizes: (point_size, scale) -> pixel_size
SIZES = [
    (16, 1),    # 16px
    (16, 2),    # 32px
    (32, 1),    # 32px
    (32, 2),    # 64px
    (128, 1),   # 128px
    (128, 2),   # 256px
    (256, 1),   # 256px
    (256, 2),   # 512px
    (512, 1),   # 512px
    (512, 2),   # 1024px
]


def main():
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    icon_dir = os.path.join(
        project_root, "Untouchable", "Assets.xcassets", "AppIcon.appiconset"
    )

    os.makedirs(icon_dir, exist_ok=True)

    # Generate each size
    for point_size, scale in SIZES:
        pixel_size = point_size * scale
        if scale == 1:
            filename = f"icon_{point_size}x{point_size}.png"
        else:
            filename = f"icon_{point_size}x{point_size}@2x.png"

        output_path = os.path.join(icon_dir, filename)
        cairosvg.svg2png(
            bytestring=SVG_ICON.encode("utf-8"),
            write_to=output_path,
            output_width=pixel_size,
            output_height=pixel_size,
        )
        print(f"  {filename} ({pixel_size}x{pixel_size}px)")

    # Also generate a 1024x1024 master for the README / marketing
    readme_icon_path = os.path.join(project_root, "icon.png")
    cairosvg.svg2png(
        bytestring=SVG_ICON.encode("utf-8"),
        write_to=readme_icon_path,
        output_width=256,
        output_height=256,
    )
    print(f"  icon.png (256x256px for README)")

    print(f"\nAll icons written to {icon_dir}")


if __name__ == "__main__":
    main()
