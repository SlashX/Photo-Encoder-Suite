# Photo Encoder Suite

**Cross-platform photo encoding suite (bash/PS1) for Termux (Android) and Windows**

> Batch photo converter with Ultra HDR, DJI metadata, Motion Photo extraction, 24 presets and profile system — v4.2

---

## Features

- **6 output formats**: AVIF, WEBP, JPEG, HEIC, PNG, JPEG XL (.jxl)
- **8 input formats**: HEIC, JPEG, PNG, WEBP, TIFF, RAW/DNG, JXL, AVIF
- **Motion Photo support**: Samsung, Google, iPhone Live Photo, DJI 4K Live Photo extraction
- **Ultra HDR (UHDR)**: Google Ultra HDR, Samsung Super HDR, Apple Adaptive HDR — detect, info, strip, extract, decode
- **HDR processing**: auto tone mapping HDR→SDR, force HDR/SDR, bit depth control (8/10/16-bit)
- **DJI Photo**: detection, 24-field CSV metadata export, GPS/gimbal/flight data, privacy strip
- **24 predefined profiles**: instagram, facebook, whatsapp, web-gallery, archive, dji-web, print-a4, max-avif and more
- **6 quality presets**: web, social, archive, print, max (transparent quality), thumb (thumbnails)
- **Profile system**: save/load full config as `.conf` files (cross-platform KEY=VALUE)
- **Auto-preset suggestion**: detects input resolution, recommends optimal preset
- **Compare mode**: per-file size comparison (original → output, ratio, savings)
- **Dry-run mode**: preview batch without converting
- **Watch mode**: auto-convert new photos in input folder
- **Watermark**: text and image watermark support
- **Media analysis**: `photo_check` with 50-field CSV export (EXIF, HDR, UHDR, DJI, GPS, Motion Photo)
- **Batch features**: skip existing, resume interrupted batch, skip duplicates (SHA256), compression report, format distribution

---

## Platforms

| Platform | Scripts | Requirements |
|----------|---------|--------------|
| **Termux (Android)** | `.sh` (bash) | ImageMagick 7.x, ExifTool (optional) |
| **Windows** | `.ps1` (PowerShell) | ImageMagick 7.x, PowerShell 5.1+ |

---

## Project Structure

```
Photo-Encoder-Suite/
├── src/
│   ├── photo_launcher.sh           # Interactive menu — 10 options (Termux)
│   ├── photo_encoder.sh            # Main conversion engine (Termux)
│   ├── photo_check.sh              # Media analysis + 50-field CSV (Termux)
│   ├── photo_encoder.ps1           # Main conversion engine (Windows)
│   ├── photo_check.ps1             # Media analysis + 50-field CSV (Windows)
│   ├── profiles/
│   │   └── photo_profiles.conf         # 22 predefined profiles
│   └── tools/
│       ├── photo_build_ultrahdr.sh     # libultrahdr compiler (Termux, optional)
│       └── photo_build_ultrahdr.ps1    # libultrahdr compiler (Windows, optional)
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
```

### Windows

- **ImageMagick 7.x** — download from [imagemagick.org](https://imagemagick.org/script/download.php)
- **PowerShell 5.1+** (included in Windows 10/11)
- **ExifTool** *(optional)* — download from [exiftool.org](https://exiftool.org)
- **jpegtran/mozjpeg** *(optional)* — lossless JPEG optimization

---

## Quick Start

### Termux

```bash
# Set execute permissions
chmod +x src/*.sh src/tools/*.sh

# Folder structure: tools/ and profiles/ subfolders are auto-detected

# Launch interactive menu
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
| 5 | Ultra HDR (detect, strip, extract, decode) |
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

24 profiles available in `profiles/photo_profiles.conf`:

`instagram` · `facebook` · `twitter` · `whatsapp` · `stories` · `web-gallery` · `web-thumb` · `web-4k` · `archive` · `archive-full` · `archive-hdr` · `print-a4` · `print-poster` · `max-avif` · `max-jpeg` · `dji-web` · `dji-clean` · `dji-archive` · `coca-web` · `coca-social` · `coca-portfolio` · `quick-small` · `quick-medium` · `quick-large`

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

---

## DJI Photo Support

- Auto-detection: Make:DJI, XMP-drone-dji, Osmo/Action/Mavic models
- **24-field CSV export**: GPS coordinates, speed, gimbal angles, flight data, serial number, firmware
- **4K Live Photo extraction**: embedded video from JPEG
- **Privacy strip**: removes serial number, GPS, XMP-drone-dji, Make, Model

---

## Ultra HDR (UHDR)

Supports Google Ultra HDR, Samsung Super HDR, Apple Adaptive HDR.

```bash
./photo_encoder.sh --uhdr detect    # scan for UHDR images
./photo_encoder.sh --uhdr info      # detailed UHDR metadata
./photo_encoder.sh --uhdr strip     # remove UHDR gainmap
./photo_encoder.sh --uhdr extract   # extract gainmap
./photo_encoder.sh --uhdr decode    # decode via libultrahdr
```

Build `libultrahdr` locally:
```bash
./tools/photo_build_ultrahdr.sh    # Termux
.\tools\photo_build_ultrahdr.ps1   # Windows
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| `Permission denied` on `.sh` | `chmod +x src/*.sh src/tools/*.sh` — profiles/ folder is read-only |
| `magick: command not found` | `pkg install imagemagick -y` (Termux) or install ImageMagick (Windows) |
| PS1 script blocked | `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned` |
| HEIC output not working | ImageMagick compiled without libheif — script auto-falls back to AVIF |
| JXL output not working | ImageMagick compiled without libjxl — script auto-falls back to AVIF |
| UHDR decode not working | Build libultrahdr with `./tools/photo_build_ultrahdr.sh` |
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

Current: **v4.2** — 10 files | 24 predefined profiles | bash/PS1 cross-platform
