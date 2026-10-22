import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';

typedef _ScaleFileC =
    ffi.Int32 Function(
      ffi.Pointer<Utf8> path,
      ffi.Uint32 maxWidth,
      ffi.Uint32 maxHeight,
      ffi.Uint32 algorithm,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>> outPtr,
      ffi.Pointer<ffi.Size> outLen,
      ffi.Pointer<ffi.Uint32> outWidth,
      ffi.Pointer<ffi.Uint32> outHeight,
    );
typedef _ScaleFileDart =
    int Function(
      ffi.Pointer<Utf8> path,
      int maxWidth,
      int maxHeight,
      int algorithm,
      ffi.Pointer<ffi.Pointer<ffi.Uint8>> outPtr,
      ffi.Pointer<ffi.Size> outLen,
      ffi.Pointer<ffi.Uint32> outWidth,
      ffi.Pointer<ffi.Uint32> outHeight,
    );

typedef _FreeC = ffi.Void Function(ffi.Pointer<ffi.Uint8> buffer, ffi.Size len);
typedef _FreeDart = void Function(ffi.Pointer<ffi.Uint8> buffer, int len);

class DartotsuRustBindings {
  static const ok = 0;
  static const unchanged = 1;

  final _ScaleFileDart scaleFile;
  final _FreeDart free;

  DartotsuRustBindings._(ffi.DynamicLibrary lib)
    : scaleFile = lib
          .lookup<ffi.NativeFunction<_ScaleFileC>>('dartotsu_image_scale_file')
          .asFunction<_ScaleFileDart>(),
      free = lib
          .lookup<ffi.NativeFunction<_FreeC>>('dartotsu_image_free')
          .asFunction<_FreeDart>();

  static DartotsuRustBindings? _instance;
  static bool _tried = false;

  static DartotsuRustBindings? get instance {
    if (_instance != null || _tried) return _instance;
    _tried = true;
    try {
      final lib = switch (Platform.operatingSystem) {
        'android' || 'linux' => ffi.DynamicLibrary.open(
          'libdartotsu_image_rust.so',
        ),
        'windows' => ffi.DynamicLibrary.open('dartotsu_image_rust.dll'),
        'ios' || 'macos' => ffi.DynamicLibrary.process(),
        _ => null,
      };
      if (lib != null) _instance = DartotsuRustBindings._(lib);
    } catch (_) {
      _instance = null;
    }
    return _instance;
  }
}
