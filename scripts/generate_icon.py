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
    <!-- Background gradient: black to dark blue -->
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0%" stop-color="#000000"/>
      <stop offset="100%" stop-color="#0A2E6E"/>
    </linearGradient>

    <!-- Subtle inner glow for depth -->
    <radialGradient id="glow" cx="0.4" cy="0.35" r="0.65">
      <stop offset="0%" stop-color="rgba(255,255,255,0.10)"/>
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

  <!-- Ripple rings centered at fingertip touch point -->
  <circle cx="512" cy="460" r="70" fill="none" stroke="white" stroke-width="18" opacity="0.50"/>
  <circle cx="512" cy="460" r="140" fill="none" stroke="white" stroke-width="14" opacity="0.30"/>
  <circle cx="512" cy="460" r="210" fill="none" stroke="white" stroke-width="12" opacity="0.16"/>

  <!-- Touch point dot -->
  <circle cx="512" cy="460" r="14" fill="white" opacity="0.95"/>

  <!-- Lucide "hand" icon (ISC license), fingers up, coming from bottom -->
  <!-- Middle fingertip at (12,2) in 24-unit space. Want it at (512,460). -->
  <!-- s=18: tx=512-12*18=296, ty=460-2*18=424 -->
  <!-- Palm extends to: 424+22*18=820, within icon bounds -->
  <g transform="translate(296, 424) scale(18)"
     fill="none" stroke="white" stroke-width="2.2"
     stroke-linecap="round" stroke-linejoin="round" opacity="0.9">
    <path d="M18 11V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2"/>
    <path d="M14 10V4a2 2 0 0 0-2-2a2 2 0 0 0-2 2v2"/>
    <path d="M10 10.5V6a2 2 0 0 0-2-2a2 2 0 0 0-2 2v8"/>
    <path d="M18 8a2 2 0 1 1 4 0v6a8 8 0 0 1-8 8h-2c-2.8 0-4.5-.86-5.99-2.34l-3.6-3.6a2 2 0 0 1 2.83-2.82L7 15"/>
  </g>

  <!-- Prohibition circle (thicker) -->
  <circle cx="512" cy="512" r="340" fill="none" stroke="url(#slashGrad)" stroke-width="68" opacity="0.92"/>

  <!-- Prohibition slash (thicker, diagonal from top-right to bottom-left) -->
  <line x1="752" y1="272" x2="272" y2="752"
        stroke="url(#slashGrad)" stroke-width="68" stroke-linecap="round" opacity="0.92"/>
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
