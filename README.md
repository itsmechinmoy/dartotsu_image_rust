# dartotsu_image_rust

Downscales images with SIMD Lanczos3 / bicubic / bilinear / nearest filtering
(`fast_image_resize`) through a small Rust FFI library built by Cargokit.

- Reads the file itself, so no image bytes are copied through Dart.
- Skips decoding entirely when the image already fits the target size.
- Returns raw RGBA pixels that Flutter decodes without an encode step.
- Two persistent worker isolates; queued work can be cancelled.
- Decodes PNG, JPEG, WebP, GIF and BMP. Corrupt files return an error instead of crashing.

```yaml
dependencies:
  dartotsu_image_rust:
    git:
      url: https://github.com/itsmechinmoy/dartotsu_image_rust.git
      ref: main
```

```dart
final provider = DartotsuScaledImage(
  id: page.url,
  loadFile: () async => File(path),
  maxWidth: 1080,
);
```

`DartotsuScaledImage` falls back to a normal decode when the image already fits,
the native library is unavailable or scaling fails.
