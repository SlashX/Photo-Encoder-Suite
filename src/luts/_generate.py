#!/usr/bin/env python3
"""
Generator for DJI D-Log .cube LUTs shipped with Photo Encoder Suite.

Produces (user-selectable):
  rec709.cube     — DJI D-Log -> Rec.709 (gamma 2.4, neutral broadcast conversion)
  natural.cube    — DJI D-Log -> natural look (soft S-curve + warm shadows)
  cinematic.cube  — DJI D-Log -> film emulation (Kodak 2383-inspired)

DJI D-Log transfer (forward encode), from DJI tech notes:
    y = log10(0.9892*x + 0.0108) * 0.256663 + 0.584555     for x > 0.0078
    y = 6.025 * x + 0.0929                                  for x <= 0.0078

Inverse (D-Log -> linear light):
    x = (10^((y - 0.584555) / 0.256663) - 0.0108) / 0.9892  for y > 0.14
    x = (y - 0.0929) / 6.025                                for y <= 0.14

Usage:
  python _generate.py                              # interactive menu
  python _generate.py --lut all --size 17          # CLI scriptable
  python _generate.py --lut cinematic --size 33    # single LUT, high quality
  python _generate.py --help                       # full help

Repo ships only 17^3 starter LUTs (rec709, natural). Cinematic and larger
sizes (33^3 / 65^3) are generated locally on demand.
"""
import argparse
import math
import os
import sys

SIZE_OPTIONS = [17, 33, 65]
LUT_CHOICES = ["rec709", "natural", "cinematic", "all"]

# ──────────────────────────────────────────────────────────────────────────────
# Transfer functions
# ──────────────────────────────────────────────────────────────────────────────

def dlog_to_linear(v):
    if v <= 0.14:
        x = (v - 0.0929) / 6.025
    else:
        x = (10 ** ((v - 0.584555) / 0.256663) - 0.0108) / 0.9892
    return max(0.0, min(1.0, x))

def clamp(v):
    return max(0.0, min(1.0, v))

def s_curve(x, strength=0.15):
    # Smooth contrast S-curve: boosts midtones, rolls off highlights/shadows
    return x + strength * math.sin(2.0 * math.pi * x) * 0.5

def linear_to_rec709_g24(x):
    # Simple 2.4 gamma — BT.1886 approximation for Rec.709 displays
    return clamp(x ** (1.0 / 2.4))

# ──────────────────────────────────────────────────────────────────────────────
# Look transforms
# ──────────────────────────────────────────────────────────────────────────────

def rec709_transform(r, g, b):
    lr, lg, lb = dlog_to_linear(r), dlog_to_linear(g), dlog_to_linear(b)
    return linear_to_rec709_g24(lr), linear_to_rec709_g24(lg), linear_to_rec709_g24(lb)

def natural_transform(r, g, b):
    lr, lg, lb = dlog_to_linear(r), dlog_to_linear(g), dlog_to_linear(b)
    # Slight warm shift in shadows (+2% red, -1% blue under 0.3)
    def warm(v, ch):
        if v >= 0.3: return v
        if ch == 'r': return clamp(v * 1.02)
        if ch == 'b': return v * 0.99
        return v
    lr, lg, lb = warm(lr, 'r'), warm(lg, 'g'), warm(lb, 'b')
    # Gamma 2.2 + gentle S-curve for pleasing contrast
    def encode(x):
        y = clamp(x ** (1.0 / 2.2))
        return clamp(s_curve(y, 0.08))
    return encode(lr), encode(lg), encode(lb)

def cinematic_transform(r, g, b):
    # Film emulation: Kodak 2383-inspired look for D-Log footage
    # - stronger S-curve (more contrast than natural)
    # - subtle desaturation (5%, luminance-preserving)
    # - warm midtone tint (reds/greens lifted, blues pulled — peaks at mid-gray)
    lr, lg, lb = dlog_to_linear(r), dlog_to_linear(g), dlog_to_linear(b)
    # Gamma 2.2 base
    gr, gg, gb = clamp(lr ** (1.0 / 2.2)), clamp(lg ** (1.0 / 2.2)), clamp(lb ** (1.0 / 2.2))
    # Stronger S-curve contrast
    gr, gg, gb = clamp(s_curve(gr, 0.12)), clamp(s_curve(gg, 0.12)), clamp(s_curve(gb, 0.12))
    # Desaturate 5% (preserve luminance via Rec.709 coefficients)
    lum = 0.2126 * gr + 0.7152 * gg + 0.0722 * gb
    sat = 0.95
    gr = lum + (gr - lum) * sat
    gg = lum + (gg - lum) * sat
    gb = lum + (gb - lum) * sat
    # Warm tint in midtones (parabola peaks at 0.5, zero at extremes)
    def midtone_weight(v):
        return 4.0 * v * (1.0 - v)
    wr = midtone_weight(gr); wg = midtone_weight(gg); wb = midtone_weight(gb)
    gr = gr + 0.012 * wr
    gg = gg + 0.006 * wg
    gb = gb - 0.008 * wb
    return clamp(gr), clamp(gg), clamp(gb)

TRANSFORMS = {
    "rec709":    ("DJI D-Log to Rec.709 (gamma 2.4)",              rec709_transform),
    "natural":   ("DJI D-Log to natural (soft S-curve, warm shadows)", natural_transform),
    "cinematic": ("DJI D-Log to cinematic (film emulation, Kodak 2383-inspired)", cinematic_transform),
}

# ──────────────────────────────────────────────────────────────────────────────
# LUT writer
# ──────────────────────────────────────────────────────────────────────────────

def write_cube(path, title, transform, size):
    lines = []
    lines.append(f'TITLE "{title}"')
    lines.append(f'LUT_3D_SIZE {size}')
    lines.append('DOMAIN_MIN 0.0 0.0 0.0')
    lines.append('DOMAIN_MAX 1.0 1.0 1.0')
    lines.append('')
    # Iteration order per .cube spec: R fastest, then G, then B
    for bi in range(size):
        b = bi / (size - 1)
        for gi in range(size):
            g = gi / (size - 1)
            for ri in range(size):
                r = ri / (size - 1)
                R, G, B = transform(r, g, b)
                lines.append(f'{R:.6f} {G:.6f} {B:.6f}')
    with open(path, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(lines) + '\n')
    kb = os.path.getsize(path) / 1024.0
    print(f"  [OK] {os.path.basename(path)}  ({size}^3, {len(lines)} lines, {kb:.0f} KB)")

def confirm_overwrite(path):
    if not os.path.exists(path):
        return True
    kb = os.path.getsize(path) / 1024.0
    while True:
        ans = input(f"  [!] {os.path.basename(path)} exista deja ({kb:.0f} KB). Suprascrie? (d/N): ").strip().lower()
        if ans in ("d", "da", "y", "yes"): return True
        if ans in ("", "n", "nu", "no"):
            print(f"  [SKIP] {os.path.basename(path)}")
            return False

# ──────────────────────────────────────────────────────────────────────────────
# Interactive menu
# ──────────────────────────────────────────────────────────────────────────────

def interactive_menu():
    print()
    print("  ╔══════════════════════════════════════════════════╗")
    print("  ║  Photo Encoder Suite — LUT Generator             ║")
    print("  ╚══════════════════════════════════════════════════╝")
    print()
    print("  Alege LUT:")
    print("    1) rec709     — D-Log -> Rec.709 broadcast (gamma 2.4)")
    print("    2) natural    — D-Log -> natural look (soft S-curve, shadows calde)")
    print("    3) cinematic  — D-Log -> film emulation (Kodak 2383-inspired)")
    print("    4) toate 3")
    print()
    while True:
        c = input("  Alege [1-4, default=4]: ").strip() or "4"
        if c in ("1","2","3","4"): break
        print("  [!] Alege 1, 2, 3 sau 4.")
    lut_map = {"1":"rec709", "2":"natural", "3":"cinematic", "4":"all"}
    lut = lut_map[c]

    print()
    print("  Alege dimensiune:")
    print("    1) 17  — compact (~130 KB/file, starter)")
    print("    2) 33  — high quality (~950 KB/file, DaVinci standard)")
    print("    3) 65  — professional (~7.5 MB/file, max precision)")
    print()
    while True:
        s = input("  Alege [1-3, default=1]: ").strip() or "1"
        if s in ("1","2","3"): break
        print("  [!] Alege 1, 2 sau 3.")
    size = {"1":17, "2":33, "3":65}[s]

    return lut, size

# ──────────────────────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="DJI D-Log LUT generator (.cube) — Photo Encoder Suite",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Exemple:\n"
               "  python _generate.py                            # interactive\n"
               "  python _generate.py --lut all --size 17\n"
               "  python _generate.py --lut cinematic --size 33\n"
               "  python _generate.py --lut rec709 --size 65\n"
    )
    parser.add_argument("--lut", choices=LUT_CHOICES, default=None,
                        help="LUT selection (default: all when args given, interactive otherwise)")
    parser.add_argument("--size", type=int, choices=SIZE_OPTIONS, default=None,
                        help="Cube grid size (default: 17 when args given)")
    args = parser.parse_args()

    # If NO args -> interactive menu. Otherwise use provided args + defaults.
    if args.lut is None and args.size is None:
        lut, size = interactive_menu()
    else:
        lut = args.lut or "all"
        size = args.size or 17

    out_dir = os.path.dirname(os.path.abspath(__file__))

    if lut == "all":
        targets = [(name, TRANSFORMS[name][0], TRANSFORMS[name][1]) for name in ("rec709","natural","cinematic")]
    else:
        title, fn = TRANSFORMS[lut]
        targets = [(lut, title, fn)]

    print()
    print(f"  [INFO] Generez {len(targets)} LUT(-uri) la {size}^3 in {out_dir}")
    print()

    written = 0; skipped = 0
    for name, title, fn in targets:
        path = os.path.join(out_dir, f"{name}.cube")
        if not confirm_overwrite(path):
            skipped += 1
            continue
        write_cube(path, title, fn, size)
        written += 1

    print()
    print(f"  [DONE] Scrise: {written} | Skip-uite: {skipped}")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n  [ABORT] Intrerupt de utilizator.")
        sys.exit(130)
