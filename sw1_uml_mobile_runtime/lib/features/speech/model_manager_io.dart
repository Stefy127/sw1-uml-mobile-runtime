import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class SpeechModelNotInstalledException implements Exception {
  @override
  String toString() => 'El modelo de voz offline aún no está instalado.';
}

class SpeechModelFiles {
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;

  const SpeechModelFiles({
    required this.encoder,
    required this.decoder,
    required this.joiner,
    required this.tokens,
  });
}

class ModelInstallProgress {
  final String fileName;
  final int downloadedBytes;
  final int? totalBytes;
  final int overallDownloadedBytes;
  final int? overallTotalBytes;

  const ModelInstallProgress({
    required this.fileName,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.overallDownloadedBytes,
    required this.overallTotalBytes,
  });

  double? get fileFraction {
    final total = totalBytes;
    if (total == null || total <= 0) return null;
    return (downloadedBytes / total).clamp(0.0, 1.0);
  }

  double? get overallFraction {
    if (totalBytes == null) return null;
    final total = overallTotalBytes;
    if (total == null || total <= 0) return null;
    return (overallDownloadedBytes / total).clamp(0.0, 1.0);
  }
}

class ModelManager {
  static const modelName = 'zipformer-es-kroko-2025-08-06';
  static const modelSize = 'aprox. 155 MB';
  static const baseUrl = 'https://huggingface.co/csukuangfj/sherpa-onnx-streaming-zipformer-es-kroko-2025-08-06/resolve/main/';
  static const _files = <String, int>{
    'encoder.onnx': 100 * 1024 * 1024,
    'decoder.onnx': 100 * 1024,
    'joiner.onnx': 100 * 1024,
    'tokens.txt': 1024,
  };
  static const _expectedSizes = <String, int>{
    'encoder.onnx': 154878102,
    'decoder.onnx': 617488,
    'joiner.onnx': 336817,
    'tokens.txt': 6144,
  };

  final http.Client _client;
  final Future<Directory> Function()? _directoryProvider;
  final Map<String, int> _minimumSizes;
  Future<void>? _installFuture;

  ModelManager({
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
    Map<String, int>? minimumSizes,
  })  : _client = client ?? http.Client(),
        _directoryProvider = directoryProvider,
        _minimumSizes = minimumSizes ?? _files;

  bool get isInstalling => _installFuture != null;

  Future<Directory> directory() async {
    final directory = _directoryProvider != null
        ? await _directoryProvider!()
        : Directory(p.join((await getApplicationSupportDirectory()).path, 'models', 'asr'));
    await directory.create(recursive: true);
    return directory;
  }

  Future<bool> isInstalled() async {
    final dir = await directory();
    for (final entry in _files.entries) {
      final file = File(p.join(dir.path, entry.key));
      if (!file.existsSync() || file.lengthSync() < (_minimumSizes[entry.key] ?? entry.value)) return false;
    }
    return true;
  }

  Future<SpeechModelFiles> files() async {
    final dir = await directory();
    if (!await isInstalled()) throw SpeechModelNotInstalledException();
    return SpeechModelFiles(
      encoder: p.join(dir.path, 'encoder.onnx'),
      decoder: p.join(dir.path, 'decoder.onnx'),
      joiner: p.join(dir.path, 'joiner.onnx'),
      tokens: p.join(dir.path, 'tokens.txt'),
    );
  }

  Future<void> installModel({
    void Function(ModelInstallProgress progress)? onProgress,
    void Function(String status)? onStatus,
  }) {
    final current = _installFuture;
    if (current != null) {
      debugPrint('INSTALL REQUEST IGNORED - already installing');
      return current;
    }
    debugPrint('INSTALL START');
    final future = _performInstall(onProgress: onProgress, onStatus: onStatus);
    _installFuture = future;
    future.then<void>(
      (_) {
        if (identical(_installFuture, future)) _installFuture = null;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_installFuture, future)) _installFuture = null;
      },
    );
    return future;
  }

  Future<void> download({
    void Function(ModelInstallProgress progress)? onProgress,
    void Function(String status)? onStatus,
  }) => installModel(onProgress: onProgress, onStatus: onStatus);

  Future<void> _performInstall({
    void Function(ModelInstallProgress progress)? onProgress,
    void Function(String status)? onStatus,
  }) async {
    if (await isInstalled()) {
      debugPrint('INSTALL COMPLETE - already installed');
      return;
    }
    final dir = await directory();
    final overallTotal = _files.keys.every(_expectedSizes.containsKey)
        ? _files.keys.fold<int>(0, (sum, name) => sum + _expectedSizes[name]!)
        : null;
    var overallDownloaded = 0;
    try {
      for (final entry in _files.entries) {
        final downloaded = await _downloadFile(
          dir,
          entry.key,
          entry.value,
          overallDownloaded,
          overallTotal,
          onProgress,
          onStatus,
        );
        overallDownloaded += downloaded;
      }
      if (!await isInstalled()) throw Exception('La instalación del modelo quedó incompleta.');
      debugPrint('INSTALL COMPLETE');
      onStatus?.call('Modelo instalado.');
    } catch (_) {
      // Los .part se conservan para que el siguiente intento pueda reanudar.
      rethrow;
    }
  }

  Future<int> _downloadFile(
    Directory dir,
    String name,
    int minimumSize,
    int overallDownloaded,
    int? overallTotal,
    void Function(ModelInstallProgress progress)? onProgress,
    void Function(String status)? onStatus,
  ) async {
    final finalFile = File(p.join(dir.path, name));
    if (finalFile.existsSync() && finalFile.lengthSync() >= (_minimumSizes[name] ?? minimumSize)) {
      debugPrint('Skipping completed $name');
      return finalFile.lengthSync();
    }

    final part = File(p.join(dir.path, '$name.part'));
    final expected = _expectedSizes[name];
    if (name == 'tokens.txt' &&
        part.existsSync() &&
        await part.length() > (expected ?? minimumSize) * 10) {
      debugPrint('Discarding inconsistent $name.part');
      await part.delete();
    }
    for (var attempt = 1; attempt <= 3; attempt++) {
      var existingBytes = part.existsSync() ? await part.length() : 0;
      final resume = existingBytes > 0;
      onStatus?.call(resume ? 'Reanudando $name desde ${_formatBytes(existingBytes)}' : 'Descargando $name');
      final uri = Uri.parse('$baseUrl$name?download=true');
      final request = http.Request('GET', uri)
        ..followRedirects = true
        ..maxRedirects = 10
        ..headers.addAll({
          'User-Agent': 'sw1-uml-mobile-runtime/1.0',
          'Accept': 'application/octet-stream',
          if (resume) 'Range': 'bytes=$existingBytes-',
        });

      debugPrint(resume ? 'Resuming $name from $existingBytes' : 'Downloading $name');
      debugPrint('URL: $uri');
      try {
        final streamed = await _client.send(request).timeout(const Duration(seconds: 30));
        debugPrint('statusCode: ${streamed.statusCode}, contentLength: ${streamed.contentLength}');
        if (streamed.statusCode != 200 && streamed.statusCode != 206) {
          throw _DownloadException('No se pudo descargar $name (${streamed.statusCode})', transient: false);
        }

        var append = resume && streamed.statusCode == 206;
        int? total = streamed.contentLength;
        if (append) {
          final range = _parseContentRange(streamed.headers['content-range']);
          if (range == null || range.start != existingBytes) {
            debugPrint('Invalid Content-Range for $name; restarting safely');
            await streamed.stream.drain();
            await part.delete();
            existingBytes = 0;
            append = false;
            continue;
          }
          total = range.total;
          if (existingBytes >= total) {
            await streamed.stream.drain();
            await part.delete();
            continue;
          }
        } else if (resume && streamed.statusCode == 200) {
          debugPrint('Range not accepted for $name; restarting from zero');
          existingBytes = 0;
          total = streamed.contentLength;
        }

        final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
        var downloaded = existingBytes;
        var loggedBucket = total == null || total <= 0 ? -1 : (downloaded * 100 ~/ total) ~/ 10;
        try {
          await for (final chunk in streamed.stream) {
            sink.add(chunk);
            downloaded += chunk.length;
            final progress = ModelInstallProgress(
              fileName: name,
              downloadedBytes: downloaded,
              totalBytes: total,
              overallDownloadedBytes: overallDownloaded + downloaded,
              overallTotalBytes: overallTotal,
            );
            onProgress?.call(progress);
            final fraction = progress.fileFraction;
            if (fraction != null) {
              final percent = (fraction * 100).clamp(0, 100).floor();
              final bucket = percent ~/ 10;
              if (bucket != loggedBucket) {
                loggedBucket = bucket;
                debugPrint('Progress $name: $percent%');
              }
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        final length = await part.length();
        if (length < (_minimumSizes[name] ?? minimumSize)) {
          await part.delete();
          throw _DownloadException('El archivo $name está vacío o incompleto.', transient: false);
        }
        if (total != null && length > total) {
          await part.delete();
          throw _DownloadException('El archivo $name excede el tamaño esperado.', transient: false);
        }
        if (total != null && length < total) {
          throw _DownloadException('La descarga de $name quedó incompleta.', transient: true);
        }
        if (finalFile.existsSync()) await finalFile.delete();
        await part.rename(finalFile.path);
        debugPrint('Completed $name');
        onStatus?.call('Descarga reanudada.');
        return length;
      } on _DownloadException catch (error) {
        if (!error.transient || attempt == 3) rethrow;
        await _retryDelay(name, attempt, onStatus);
      } on Object catch (error) {
        if (!_isTransient(error) || attempt == 3) rethrow;
        await _retryDelay(name, attempt, onStatus);
      }
    }
    throw StateError('Descarga no completada: $name');
  }

  Future<void> _retryDelay(String name, int attempt, void Function(String status)? onStatus) async {
    final seconds = 1 << attempt;
    debugPrint('Connection interrupted for $name; retrying $attempt/3');
    onStatus?.call('Conexión interrumpida. Reintentando $attempt/3...');
    await Future<void>.delayed(Duration(seconds: seconds));
  }

  bool _isTransient(Object error) =>
      error is http.ClientException || error is SocketException || error is TimeoutException;

  _ContentRange? _parseContentRange(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value);
    if (match == null) return null;
    return _ContentRange(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  void dispose() => _client.close();
}

class _ContentRange {
  final int start;
  final int end;
  final int total;
  const _ContentRange(this.start, this.end, this.total);
}

class _DownloadException implements Exception {
  final String message;
  final bool transient;
  const _DownloadException(this.message, {required this.transient});

  @override
  String toString() => message;
}
