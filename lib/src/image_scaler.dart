import 'dart:async';
import 'dart:collection';
import 'dart:ffi' as ffi;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'ffi_bindings.dart';

enum DartotsuScaleAlgorithm { nearest, bilinear, bicubic, lanczos }

class ScaledPixels {
  final Uint8List rgba;
  final int width;
  final int height;

  const ScaledPixels(this.rgba, this.width, this.height);
}

class ScaleTicket {
  final Future<ScaledPixels?> result;
  final void Function() _cancel;

  ScaleTicket._(this.result, this._cancel);

  void cancel() => _cancel();
}

class _Request {
  final int id;
  final String path;
  final int maxWidth;
  final int maxHeight;
  final int algorithm;

  const _Request(this.id, this.path, this.maxWidth, this.maxHeight, this.algorithm);
}

class _Response {
  final int id;
  final TransferableTypedData? pixels;
  final int width;
  final int height;

  const _Response(this.id, this.pixels, this.width, this.height);
}

void _workerMain(SendPort parent) {
  final inbox = ReceivePort();
  parent.send(inbox.sendPort);
  final bindings = DartotsuRustBindings.instance;
  inbox.listen((message) {
    final request = message as _Request;
    parent.send(_run(bindings, request));
  });
}

_Response _run(DartotsuRustBindings? bindings, _Request r) {
  if (bindings == null) return _Response(r.id, null, 0, 0);
  final path = r.path.toNativeUtf8();
  final outPtr = malloc<ffi.Pointer<ffi.Uint8>>();
  final outLen = malloc<ffi.Size>();
  final outW = malloc<ffi.Uint32>();
  final outH = malloc<ffi.Uint32>();
  try {
    final code = bindings.scaleFile(
      path,
      r.maxWidth,
      r.maxHeight,
      r.algorithm,
      outPtr,
      outLen,
      outW,
      outH,
    );
    if (code != DartotsuRustBindings.ok) return _Response(r.id, null, 0, 0);
    final buffer = outPtr.value;
    final len = outLen.value;
    final data = TransferableTypedData.fromList([buffer.asTypedList(len)]);
    bindings.free(buffer, len);
    return _Response(r.id, data, outW.value, outH.value);
  } finally {
    malloc.free(path);
    malloc.free(outPtr);
    malloc.free(outLen);
    malloc.free(outW);
    malloc.free(outH);
  }
}

class _Worker {
  final SendPort port;
  int? busyWith;

  _Worker(this.port);
}

class _Job {
  final _Request request;
  final Completer<ScaledPixels?> done = Completer();
  bool cancelled = false;

  _Job(this.request);
}

class _Pool {
  static const _maxWorkers = 2;

  final _queue = Queue<_Job>();
  final _running = <int, _Job>{};
  final _workers = <_Worker>[];
  final _inbox = ReceivePort();
  var _spawning = 0;
  var _nextId = 0;

  _Pool() {
    _inbox.listen(_onMessage);
  }

  void _onMessage(dynamic message) {
    if (message is SendPort) {
      _spawning--;
      _workers.add(_Worker(message));
      _pump();
      return;
    }
    final response = message as _Response;
    final job = _running.remove(response.id);
    for (final w in _workers) {
      if (w.busyWith == response.id) w.busyWith = null;
    }
    if (job != null && !job.done.isCompleted) {
      final data = response.pixels;
      job.done.complete(
        job.cancelled || data == null
            ? null
            : ScaledPixels(
                data.materialize().asUint8List(),
                response.width,
                response.height,
              ),
      );
    }
    _pump();
  }

  ScaleTicket submit(String path, int maxW, int maxH, int algorithm) {
    final job = _Job(_Request(_nextId++, path, maxW, maxH, algorithm));
    _queue.add(job);
    _pump();
    return ScaleTicket._(job.done.future, () {
      job.cancelled = true;
      if (_queue.remove(job) && !job.done.isCompleted) job.done.complete(null);
    });
  }

  void _pump() {
    while (_queue.isNotEmpty) {
      _Worker? free;
      for (final w in _workers) {
        if (w.busyWith == null) {
          free = w;
          break;
        }
      }
      if (free == null) {
        if (_workers.length + _spawning < _maxWorkers) {
          _spawning++;
          Isolate.spawn(_workerMain, _inbox.sendPort).catchError((Object _) {
            _spawning--;
            while (_queue.isNotEmpty) {
              _queue.removeFirst().done.complete(null);
            }
            return Isolate.current;
          });
        }
        return;
      }
      final job = _queue.removeFirst();
      if (job.cancelled) continue;
      free.busyWith = job.request.id;
      _running[job.request.id] = job;
      free.port.send(job.request);
    }
  }
}

class DartotsuImageRust {
  DartotsuImageRust._();

  static final _pool = _Pool();

  static bool get isSupported => DartotsuRustBindings.instance != null;

  /// Scales the image file at [path] down to fit inside [maxWidth] x
  /// [maxHeight] (0 leaves that axis unbounded). The result is RGBA8 pixels,
  /// or null when the image already fits, cannot be decoded, or the native
  /// library is missing.
  static ScaleTicket scale(
    String path, {
    int maxWidth = 0,
    int maxHeight = 0,
    DartotsuScaleAlgorithm algorithm = DartotsuScaleAlgorithm.lanczos,
  }) => _pool.submit(path, maxWidth, maxHeight, algorithm.index);
}
