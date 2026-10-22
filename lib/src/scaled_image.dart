import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'image_scaler.dart';

/// An [ImageProvider] that decodes [loadFile]'s image already downscaled to
/// fit [maxWidth] x [maxHeight], so results live in Flutter's own
/// [ImageCache] and no encoded intermediate is produced.
class DartotsuScaledImage extends ImageProvider<DartotsuScaledImage> {
  final String id;
  final Future<File?> Function() loadFile;
  final int maxWidth;
  final int maxHeight;
  final DartotsuScaleAlgorithm algorithm;

  const DartotsuScaledImage({
    required this.id,
    required this.loadFile,
    this.maxWidth = 0,
    this.maxHeight = 0,
    this.algorithm = DartotsuScaleAlgorithm.lanczos,
  });

  @override
  Future<DartotsuScaledImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    DartotsuScaledImage key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(_load(key, decode));

  Future<ImageInfo> _load(
    DartotsuScaledImage key,
    ImageDecoderCallback decode,
  ) async {
    final file = await loadFile();
    if (file == null) throw StateError('Image is not available: $id');
    final ticket = DartotsuImageRust.scale(
      file.path,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      algorithm: algorithm,
    );
    final scaled = await ticket.result;
    if (scaled == null) {
      final buffer = await ui.ImmutableBuffer.fromFilePath(file.path);
      final codec = await decode(buffer);
      final frame = await codec.getNextFrame();
      codec.dispose();
      return ImageInfo(image: frame.image);
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(scaled.rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: scaled.width,
      height: scaled.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
    return ImageInfo(image: frame.image);
  }

  @override
  bool operator ==(Object other) =>
      other is DartotsuScaledImage &&
      other.id == id &&
      other.maxWidth == maxWidth &&
      other.maxHeight == maxHeight &&
      other.algorithm == algorithm;

  @override
  int get hashCode => Object.hash(id, maxWidth, maxHeight, algorithm);

  @override
  String toString() => 'DartotsuScaledImage($id, $maxWidth x $maxHeight)';
}
