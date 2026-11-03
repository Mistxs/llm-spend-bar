#!/usr/bin/env python3
"""Рисует AppIcon.icns без внешних зависимостей.

Запуск: python3 tools/build-app-icon.py
"""

import binascii
import math
import os
import struct
import subprocess
import tempfile
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SIZE = 1024
SS = 2  # supersampling


def chunk(kind: bytes, data: bytes) -> bytes:
    return (
        struct.pack(">I", len(data))
        + kind
        + data
        + struct.pack(">I", binascii.crc32(kind + data) & 0xFFFFFFFF)
    )


def write_png(path: str, width: int, height: int, pixels: bytearray) -> None:
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])
    payload = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
        + chunk(b"IEND", b"")
    )
    with open(path, "wb") as handle:
        handle.write(payload)


def blend(dst, index, color, alpha):
    if alpha <= 0:
        return
    a = min(1.0, alpha)
    inv = 1.0 - a
    dst[index] = int(dst[index] * inv + color[0] * a)
    dst[index + 1] = int(dst[index + 1] * inv + color[1] * a)
    dst[index + 2] = int(dst[index + 2] * inv + color[2] * a)
    dst[index + 3] = int(dst[index + 3] * inv + 255 * a)


def rounded_rect(pixels, width, height, x0, y0, x1, y1, radius, color, alpha=1.0):
    for y in range(max(0, int(y0)), min(height, int(y1))):
        for x in range(max(0, int(x0)), min(width, int(x1))):
            cx = min(max(x + 0.5, x0 + radius), x1 - radius)
            cy = min(max(y + 0.5, y0 + radius), y1 - radius)
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            if dx * dx + dy * dy <= radius * radius:
                blend(pixels, (y * width + x) * 4, color, alpha)


def gradient_rounded_rect(pixels, width, height, x0, y0, x1, y1, radius):
    for y in range(max(0, int(y0)), min(height, int(y1))):
        for x in range(max(0, int(x0)), min(width, int(x1))):
            cx = min(max(x + 0.5, x0 + radius), x1 - radius)
            cy = min(max(y + 0.5, y0 + radius), y1 - radius)
            dx = x + 0.5 - cx
            dy = y + 0.5 - cy
            if dx * dx + dy * dy > radius * radius:
                continue
            t = (x - x0 + y - y0) / max(1.0, (x1 - x0) + (y1 - y0))
            r = int(29 + (124 - 29) * t)
            g = int(78 + (58 - 78) * t)
            b = int(216 + (237 - 216) * t)
            blend(pixels, (y * width + x) * 4, (r, g, b), 1.0)


def render(size: int) -> bytearray:
    pixels = bytearray(size * size * 4)
    margin = int(size * 0.08)
    radius = int(size * 0.22)
    gradient_rounded_rect(pixels, size, size, margin, margin, size - margin, size - margin, radius)

    # Лёгкая внутренняя рамка.
    rounded_rect(pixels, size, size, margin + 3, margin + 3, size - margin - 3, size - margin - 3,
                 max(1, radius - 3), (255, 255, 255), 0.08)

    bar_width = int(size * 0.115)
    gap = int(size * 0.062)
    total = bar_width * 3 + gap * 2
    start_x = (size - total) // 2
    base_y = int(size * 0.76)
    heights = [int(size * 0.27), int(size * 0.40), int(size * 0.53)]
    colors = [(52, 211, 153), (251, 191, 36), (248, 113, 113)]
    bar_radius = max(2, bar_width // 3)

    for index in range(3):
        x = start_x + index * (bar_width + gap)
        y = base_y - heights[index]
        rounded_rect(pixels, size, size, x, y, x + bar_width, base_y, bar_radius, (255, 255, 255), 0.16)
        rounded_rect(pixels, size, size, x, y, x + bar_width, base_y, bar_radius, colors[index], 0.95)
        # Блик сверху.
        rounded_rect(pixels, size, size, x + bar_width * 0.18, y + bar_width * 0.18,
                     x + bar_width * 0.82, y + bar_width * 0.46, bar_radius // 2,
                     (255, 255, 255), 0.28)

    return pixels


def downsample(pixels: bytearray, size: int, factor: int) -> bytearray:
    out = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            r = g = b = a = 0
            for dy in range(factor):
                for dx in range(factor):
                    idx = ((y * factor + dy) * (size * factor) + (x * factor + dx)) * 4
                    r += pixels[idx]
                    g += pixels[idx + 1]
                    b += pixels[idx + 2]
                    a += pixels[idx + 3]
            n = factor * factor
            idx = (y * size + x) * 4
            out[idx] = r // n
            out[idx + 1] = g // n
            out[idx + 2] = b // n
            out[idx + 3] = a // n
    return out


def main() -> None:
    big = render(SIZE * SS)
    icon = downsample(big, SIZE, SS)
    master = os.path.join(ROOT, "docs", "app-icon.png")
    os.makedirs(os.path.dirname(master), exist_ok=True)
    write_png(master, SIZE, SIZE, icon)

    iconset = os.path.join(ROOT, "build", "AppIcon.iconset")
    os.makedirs(iconset, exist_ok=True)
    for name, size in [
        ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
        ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
        ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
        ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
        ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
    ]:
        target = os.path.join(iconset, name)
        subprocess.run(["sips", "-z", str(size), str(size), master, "--out", target],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    resources = os.path.join(ROOT, "Resources")
    os.makedirs(resources, exist_ok=True)
    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(resources, "AppIcon.icns")],
                   check=True)
    print(f"icon: {master}")
    print(f"icns: {os.path.join(resources, 'AppIcon.icns')}")


if __name__ == "__main__":
    main()
