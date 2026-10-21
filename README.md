# dartotsu_image_rust

High-performance Rust & SIMD image processing Flutter plugin for Dartotsu (Lanczos3, Bicubic, Bilinear, Nearest Neighbor, and optional libvips).

## Features
- **SIMD Resampling**: Powered by `fast_image_resize` (ARM NEON & x86 AVX2) and `rayon` for multi-threaded CPU scaling.
- **Multiple Resampling Filters**: Lanczos3, Bicubic (Catmull-Rom), Bilinear, Nearest Neighbor.
- **Rich Format Decoding**: Decodes PNG, JPEG, WebP, AVIF, GIF, BMP, TIFF, ICO, QOI, TGA, and HDR.
- **libvips Ready**: Optional feature-flagged libvips binding support.
- **Cross-Platform**: Android, iOS, macOS, Windows, Linux via Cargokit.

## Usage

```yaml
dependencies:
  dartotsu_image_rust:
    git:
      url: https://github.com/itsmechinmoy/dartotsu_image_rust.git
      ref: main
```

```dart
import 'package:dartotsu_image_rust/dartotsu_image_rust.dart';

final scaledBytes = await DartotsuImageRust.scale(
  sourceBytes: imageBytes,
  targetWidth: 1080,
  targetHeight: 1920,
  filter: RustImageFilter.lanczos3,
);
```
