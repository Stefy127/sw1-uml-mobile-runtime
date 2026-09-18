import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'llm_install_progress.dart';

class LlmModelManager {
  static const modelFileName = 'Qwen3-0.6B-Q4_K_M.gguf';
  static const modelUrl = 'https://huggingface.co/QuantFactory/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B.Q4_K_M.gguf?download=true';
  static const minimumBytes = 300 * 1024 * 1024;
  final http.Client _client;
  Future<void>? _installFuture;
  final Future<Directory> Function()? _directoryProvider;

  LlmModelManager({http.Client? client, Future<Directory> Function()? directoryProvider})
      : _client = client ?? http.Client(),
        _directoryProvider = directoryProvider;

  bool get isInstalling => _installFuture != null;

  Future<Directory> directory() async {
    final root = _directoryProvider != null
        ? await _directoryProvider!()
        : Directory(p.join((await getApplicationSupportDirectory()).path, 'models', 'llm', 'qwen3-0.6b'));
    await root.create(recursive: true);
    return root;
  }

  Future<String> modelPath() async => p.join((await directory()).path, modelFileName);

  Future<bool> isInstalled() async {
    final file = File(await modelPath());
    return file.existsSync() && await file.length() >= minimumBytes;
  }

  Future<void> installModel({void Function(LlmInstallProgress progress)? onProgress}) {
    final current = _installFuture;
    if (current != null) return current;
    debugPrint('LLM INSTALL START');
    final future = _performInstallWithRetries(onProgress);
    _installFuture = future;
    future.whenComplete(() {
      if (identical(_installFuture, future)) _installFuture = null;
    });
    return future;
  }

  Future<void> _performInstallWithRetries(void Function(LlmInstallProgress progress)? onProgress) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        await _performInstallOnce(onProgress);
        debugPrint('LLM INSTALL COMPLETE');
        return;
      } catch (error) {
        lastError = error;
        final transient = error is http.ClientException || error is SocketException || error is TimeoutException;
        if (!transient || attempt == 3) rethrow;
        await Future<void>.delayed(Duration(seconds: 1 << attempt));
      }
    }
    throw lastError ?? StateError('Descarga LLM no completada.');
  }

  Future<void> _performInstallOnce(void Function(LlmInstallProgress progress)? onProgress) async {
    if (await isInstalled()) return;
    final dir = await directory();
    final target = File(p.join(dir.path, modelFileName));
    final part = File('${target.path}.part');
    var existing = part.existsSync() ? await part.length() : 0;
    final request = http.Request('GET', Uri.parse(modelUrl))
      ..followRedirects = true
      ..maxRedirects = 10
      ..headers.addAll({'User-Agent': 'sw1-uml-mobile-runtime/1.0', 'Accept': 'application/octet-stream', if (existing > 0) 'Range': 'bytes=$existing-'});
    debugPrint('Downloading $modelFileName');
    debugPrint('URL: $modelUrl');
    final response = await _client.send(request).timeout(const Duration(minutes: 5));
    debugPrint('statusCode: ${response.statusCode}, contentLength: ${response.contentLength}');
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw Exception('No se pudo descargar $modelFileName (${response.statusCode})');
    }
    final append = existing > 0 && response.statusCode == 206;
    if (!append) existing = 0;
    final total = response.contentLength == null ? null : existing + response.contentLength!;
    final sink = part.openWrite(mode: append ? FileMode.append : FileMode.write);
    var downloaded = existing;
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        onProgress?.call(LlmInstallProgress(downloaded, total));
        if (total != null && total > 0) {
          final percent = ((downloaded / total) * 100).clamp(0, 100).floor();
          debugPrint('Progress LLM: $percent%');
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (await part.length() < minimumBytes) {
      throw Exception('El modelo LLM está vacío o incompleto.');
    }
    if (target.existsSync()) await target.delete();
    await part.rename(target.path);
    debugPrint('Completed $modelFileName');
  }

  void dispose() => _client.close();
}
