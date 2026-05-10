# Photo Encoder Suite

**Cross-platform photo encoding suite (bash/PS1) for Termux (Android), Linux, macOS and Windows**

> Batch photo converter with Ultra HDR (incl. HEIC HDR → UHDR JPEG conversion), DJI metadata, D-Log 3D LUT grading, Motion Photo extraction + shareable remux, 29 presets and profile system — v4.8

---

## Features

- **6 output formats**: AVIF, WEBP, JPEG, HEIC, PNG, JPEG XL (.jxl)
- **8 input formats**: HEIC, JPEG, PNG, WEBP, TIFF, RAW/DNG, JXL, AVIF
- **Motion Photo support**: Samsung, Google, iPhone Live Photo, DJI 4K Live Photo extraction
- **Motion Shareable** (`--motion-shareable`): ffmpeg faststart remux + orientation inject for instant preview (WhatsApp, browsers); best-effort moov-position detection when ffmpeg unavailable
- **Ultra HDR (UHDR)**: Google Ultra HDR, Samsung Super HDR, Apple Adaptive HDR — detect, info, strip, extract, decode, **convert** (HEIC HDR → Ultra HDR JPEG with auto-hybrid preserve/regenerate gainmap via libheif + libultrahdr)
- **HDR processing**: auto tone mapping HDR→SDR, force HDR/SDR, bit depth control (8/10/16-bit)
- **DJI Photo**: detection, 24-field CSV metadata export, GPS/gimbal/flight data, privacy strip, clean mode (strip telemetry + binary debug), burst-group handling (Action cameras), **D-Log / D-LogM 3D LUT color grading** (ffmpeg lut3d, ship with rec709 + natural .cube files)
- **Perceptual duplicates**: `--skip-similar` during conversion + `--find-duplicates` in photo_check (dHash 64-bit, Hamming distance)
- **29 predefined profiles**: instagram, facebook, whatsapp, web-gallery, archive, dji-web, dji-clean, dji-web-lut, dji-archive-lut, print-a4, max-avif, motion-share and more
- **6 quality presets**: web, social, archive, print, max (transparent quality), thumb (thumbnails)
- **Profile system**: save/load full config as `.conf` files (cross-platform KEY=VALUE) — with **schema validation, diff tool, and template generator** (v4.8)
- **Test suite** (v4.8): `tests/run_tests.sh` / `run_tests.ps1` — assertion framework + unit & integration tests (skip elegant when deps missing)
- **Auto-preset suggestion**: detects input resolution, recommends optimal preset
- **Compare mode**: per-file size comparison (original → output, ratio, savings)
- **Dry-run mode**: preview batch without converting
- **Watch mode**: auto-convert new photos in input folder
- **Watermark**: text and image watermark support
- **Media analysis**: `photo_check` with 54-field CSV export (EXIF, HDR, UHDR, DJI, GPS, Motion Photo, DNG, duplicates)
- **Batch features**: skip existing, resume interrupted batch, skip duplicates (SHA256), compression report, format distribution

---

## Platforms

| Platform | Scripts | Requirements |
|----------|---------|--------------|
| **Termux (Android)** | `.sh` (bash) | ImageMagick 7.x, ExifTool (optional) |
| **Linux** | `.sh` (bash 4+) | ImageMagick 7.x via `apt`/`dnf`/`pacman`, ExifTool (optional) |
| **macOS** | `.sh` (bash 4+) | `brew install bash imagemagick exiftool` |
| **Windows** | `.ps1` (PowerShell) | ImageMagick 7.x, PowerShell 5.1+ |

---

## Project Structure

```
Photo-Encoder-Suite/
├── src/
│   ├── photo_common.sh             # Cross-platform foundation + profile schema/validation (v4.8)
│   ├── photo_profile_lib.ps1       # PS1 mirror of profile schema/validation (NEW v4.8)
│   ├── photo_launcher.sh           # Interactive menu — 10 options (Termux/Linux/macOS)
│   ├── photo_encoder.sh            # Main conversion engine (Termux/Linux/macOS)
│   ├── photo_check.sh              # Media analysis + 54-field CSV (Termux/Linux/macOS)
│   ├── photo_encoder.ps1           # Main conversion engine (Windows)
│   ├── photo_check.ps1             # Media analysis + 54-field CSV (Windows)
│   ├── profiles/
│   │   └── photo_profiles.conf         # 29 predefined profiles
│   └── tools/
│       ├── photo_build_ultrahdr.sh     # libultrahdr compiler (Termux/Linux/macOS, optional)
│       ├── photo_build_ultrahdr.ps1    # libultrahdr compiler (Windows, optional)
│       ├── photo_build_libheif.ps1     # libheif build via vcpkg (Windows, optional)
│       ├── photo_profile_diff.sh/.ps1  # Diff two profiles (NEW v4.8)
│       └── photo_profile_template.sh/.ps1  # Generate UserProfiles/_template.conf (NEW v4.8)
├── tests/                          # Test framework + suites (NEW v4.8)
│   ├── framework.sh / .ps1         # Assertion library
│   ├── run_tests.sh / .ps1         # Discovery + runner
│   ├── unit/                       # Schema, validation, diff, helpers
│   ├── integration/                # Encode smoke + check_csv
│   └── fixtures/                   # Synth PNG/JPEG/HEIC samples
├── docs/
│   ├── photo_info.txt              # Full setup & usage documentation
│   └── photo_changelog.txt         # Version history
├── .gitignore
├── LICENSE
└── README.md
```

---

## Requirements

### Termux (Android)

```bash
pkg update -y
pkg install imagemagick -y                       # required
pkg install perl -y && cpan Image::ExifTool      # recommended
pkg install libjpeg-turbo -y                     # optional (lossless JPEG)
pkg install libheif -y                           # optional (Ultra HDR convert modes)
pkg install ffmpeg -y                            # optional (motion shareable, dji-lut, uhdr convert-regen)
```

### Linux (Debian / Ubuntu / Fedora / Arch)

```bash
# Debian / Ubuntu
sudo apt install bash imagemagick libimage-exiftool-perl libheif-examples ffmpeg

# Fedora
sudo dnf install bash ImageMagick perl-Image-ExifTool libheif-tools ffmpeg

# Arch Linux
sudo pacman -S bash imagemagick perl-image-exiftool libheif ffmpeg
```

### macOS

```bash
# Required: bash 4+ (Apple ships bash 3.2)
brew install bash

# Required: ImageMagick
brew install imagemagick

# Optional but recommended
brew install exiftool libheif ffmpeg
```

### Windows

- **ImageMagick 7.x** — download from [imagemagick.org](https://imagemagick.org/script/download.php)
- **PowerShell 5.1+** (included in Windows 10/11)
- **ExifTool** *(optional)* — download from [exiftool.org](https://exiftool.org)
- **ffmpeg** *(optional, for `--motion-shareable` faststart remux)* — portable: drop `ffmpeg.exe` next to `photo_encoder.ps1` (get it from [gyan.dev](https://www.gyan.dev/ffmpeg/builds/) static builds, no PATH edit needed). System-wide: `winget install Gyan.FFmpeg`
- **jpegtran/mozjpeg** *(optional)* — lossless JPEG optimization

---

## Quick Start

### Termux

```bash
# Set execute permissions
chmod +x src/*.sh src/tools/*.sh

# Folder structure: tools/ and profiles/ subfolders are auto-detected
# (folders for InputPhotos / OutputPhotos / UserProfiles live under
#  /storage/emulated/0/Media/ — unchanged behavior)

# Launch interactive menu
cd src
./photo_launcher.sh
```

### Linux / macOS

```bash
# Set execute permissions
chmod +x src/*.sh src/tools/*.sh

# Launch interactive menu — InputPhotos/OutputPhotos/UserProfiles/luts/profiles
# are auto-created next to the script (parity with Windows PS1).
cd src
./photo_launcher.sh
```

### Windows (PowerShell)

```powershell
# Allow script execution (run once as Administrator)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned

# Launch
cd src
.\photo_encoder.ps1
```

---

## Menu Options — `photo_launcher.sh`

| Option | Description |
|--------|-------------|
| 1 | Quick convert (format + quality only) |
| 2 | Advanced convert (all options) |
| 3 | Convert with profile (instagram, web, dji, etc.) |
| 4 | Motion / Live Photo extraction |
| 5 | Ultra HDR (detect, strip, extract, decode, convert / convert-preserve / convert-regen) |
| 6 | DJI Photo (metadata export + privacy strip) |
| 7 | Lossless JPEG optimization |
| 8 | Watch mode (auto-convert new photos) |
| 9 | Check media files (analysis + CSV export) |
| 0 | Exit |

---

## Output Formats & Quality Presets

| Format | web | social | archive | print | max | thumb | HDR capable |
|--------|-----|--------|---------|-------|-----|-------|-------------|
| AVIF | 40 | 35 | 60 | 65 | 80 | 25 | ✅ |
| WEBP | 75 | 70 | 90 | 92 | 95 | 50 | — |
| JPEG | 82 | 78 | 95 | 97 | 98 | 60 | — |
| HEIC | 50 | 45 | 70 | 75 | 85 | 30 | ✅ |
| PNG | — | — | lossless | lossless | — | — | — |
| JXL | 45 | 40 | 65 | 70 | 80 | 25 | ✅ |

---

## Predefined Profiles

27 profiles available in `profiles/photo_profiles.conf`:

`instagram` · `facebook` · `twitter` · `whatsapp` · `stories` · `web-gallery` · `web-thumb` · `web-4k` · `archive` · `archive-full` · `archive-hdr` · `print-a4` · `print-poster` · `max-avif` · `max-jpeg` · `dji-web` · `dji-clean` · `dji-privacy` · `dji-archive` · `coca-web` · `coca-social` · `coca-portfolio` · `quick-small` · `quick-medium` · `quick-large` · `motion-share` · `motion-share-only`

```bash
# Use a profile (Termux)
./photo_encoder.sh --profile instagram -i InputPhotos/ -o OutputPhotos/

# Use a profile (Windows)
.\photo_encoder.ps1 -Profile instagram -InputDir InputPhotos\ -OutputDir OutputPhotos\
```

---

## Profile System (save/load)

- Save full configuration to `UserProfiles/*.conf` at end of session
- Load saved profiles at next launch via interactive menu
- Cross-platform format: `KEY=VALUE` — compatible bash/PS1
- Two separate locations:
  - `profiles/` — predefined profiles (`photo_profiles.conf`, read-only, CLI `--profile`)
  - `UserProfiles/` — user-saved profiles (interactive save/load)

### Profile Audit (v4.8)

Schema-aware validation, diff and template generation for both profile formats:

```bash
# Validate predefined profiles
bash -c 'source src/photo_common.sh && photo_validate_predefined_profiles src/profiles/photo_profiles.conf'

# Diff two UserProfiles
bash src/tools/photo_profile_diff.sh UserProfiles/old.conf UserProfiles/new.conf

# Diff two predefined entries
bash src/tools/photo_profile_diff.sh --predefined instagram facebook

# Generate UserProfiles/_template.conf with all keys + comments
bash src/tools/photo_profile_template.sh
```

Windows equivalents (`photo_profile_diff.ps1`, `photo_profile_template.ps1`) ship the same flags.
On UserProfile load, validation runs automatically — invalid values warn in interactive mode and abort when `PHOTO_NONINTERACTIVE=1` (or `$env:PHOTO_NONINTERACTIVE='1'`).

---

## Testing (v4.8)

```bash
# Bash (Termux / Linux / macOS)
bash tests/run_tests.sh                    # all tests
bash tests/run_tests.sh "test_profile_*"   # filter by name

# PowerShell (Windows)
pwsh tests/run_tests.ps1
```

The runner discovers `tests/test_*`, `tests/unit/test_*`, and `tests/integration/test_*`, captures per-test logs in `tests/results/`, and prints a `Pass / Fail / Skip` summary. Tests that need ImageMagick / ExifTool / libheif / sample images skip gracefully (exit 77) instead of failing on systems without those dependencies.

To regenerate fixture images first:

```bash
bash tests/fixtures/generate_samples.sh        # PNG + JPEG + HEIC (HEIC best-effort)
pwsh tests/fixtures/generate_samples.ps1
```

---

## DJI Photo Support

- Auto-detection: Make:DJI, XMP-drone-dji, Osmo/Action/Mavic models
- **24-field CSV export**: GPS coordinates, speed, gimbal angles, flight data, serial number, firmware
- **4K Live Photo extraction**: embedded video from JPEG
- **Clean mode** (`--dji clean`): strips serial number (3 EXIF locations) + XMP-drone-dji telemetry + binary debug (~65KB per photo on Action 6), keeps GPS and camera data — for private sharing
- **Privacy strip** (`--dji privacy-strip`): nuclear — removes serial, GPS, XMP-drone-dji, Make, Model — for public sharing
- **Burst-group handling** (`--dji-burst-group first|all|skip`): filename-based detection (`DJI_YYYYMMDDHHMMSS_SEQ_D_NNN.JPG`) for Action cameras

---

## Ultra HDR (UHDR)

Supports Google Ultra HDR, Samsung Super HDR, Apple Adaptive HDR.

```bash
./photo_encoder.sh --uhdr detect             # scan for UHDR images
./photo_encoder.sh --uhdr info               # detailed UHDR metadata
./photo_encoder.sh --uhdr strip              # remove UHDR gainmap
./photo_encoder.sh --uhdr extract            # extract gainmap
./photo_encoder.sh --uhdr decode             # decode via libultrahdr
./photo_encoder.sh --uhdr convert            # HEIC HDR → Ultra HDR JPEG (auto-hybrid)
./photo_encoder.sh --uhdr convert-preserve   # preserve OEM gainmap (Samsung / Apple)
./photo_encoder.sh --uhdr convert-regen      # regenerate gainmap from HDR pixels (P010)
```

Optional `--uhdr-gainmap-quality <1-100>` for convert modes (default: `clamp(base-5, 60, 90)`).

Build dependencies for Ultra HDR:
```bash
# libultrahdr (required for decode + convert)
./tools/photo_build_ultrahdr.sh          # Termux
.\tools\photo_build_ultrahdr.ps1         # Windows

# libheif (required for convert* modes)
pkg install libheif -y                   # Termux
apt install libheif-examples             # Debian/Ubuntu
.\tools\photo_build_libheif.ps1          # Windows (vcpkg + Visual Studio)
```

---

## Cross-platform bash (v4.7)

The bash side runs on **Termux (Android), Linux, and macOS** from a single codebase.

- `photo_common.sh` is sourced at the top of every `.sh` file and handles platform detection (`uname -s` + Termux discriminator), path resolution, GNU vs BSD command differences (`stat`, `sed -i`, `mktemp`, `readlink -f`, `grep -P`, `date`, `du`, `df`), wake-lock / notify / open-folder wrappers, and per-OS install hints.
- **Termux paths are unchanged** — `/storage/emulated/0/Media/InputPhotos`, etc. Existing users see zero migration.
- **Linux / macOS** auto-create `InputPhotos/`, `OutputPhotos/`, `UserProfiles/`, `luts/`, `profiles/`, `tools/` next to the launcher script (parity with Windows PS1 `$PSScriptRoot`).
- `bash 4+` is required — macOS ships bash 3.2 by default; install a modern bash with `brew install bash`.
- Notification at the end of large batches (`termux-notification` / `notify-send` / `osascript`).
- Optional "Open output folder?" prompt at end of run (`termux-open` / `xdg-open` / `open`).

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Permission denied` on `.sh` | `chmod +x src/*.sh src/tools/*.sh` — profiles/ folder is read-only |
| `magick: command not found` | Termux: `pkg install imagemagick`; Linux: `apt/dnf/pacman install imagemagick`; macOS: `brew install imagemagick` |
| `bash: bad substitution` on macOS | Apple's bash 3.2 — install bash 4+: `brew install bash` |
| PS1 script blocked | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
| HEIC output not working | ImageMagick compiled without libheif — script auto-falls back to AVIF |
| JXL output not working | ImageMagick compiled without libjxl — script auto-falls back to AVIF |
| UHDR decode/convert not working | Build libultrahdr with `./tools/photo_build_ultrahdr.sh` (cross-platform) |
| DJI GPS export empty | Image not filmed with GPS-enabled DJI RC or DJI Mimo app |

---

## License

[MIT License](LICENSE) — free to use, modify and distribute.

---

## Support

If you find this project useful, consider a small donation — it helps keep the development going!

[💙 Donate via PayPal](https://paypal.me/TiberiuDobrescu)

---

## Changelog

See [docs/photo_changelog.txt](docs/photo_changelog.txt) for full version history.

Current: **v4.8** — profile audit system + test suite | 29 predefined profiles | bash (Termux/Linux/macOS) + PS1 (Windows)
