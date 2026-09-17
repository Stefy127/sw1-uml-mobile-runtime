import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sw1_uml_mobile_runtime/features/speech/model_manager_io.dart';

class _ModelClient extends http.BaseClient {
  final int statusCode;
  final bool empty;
  final bool nullContentLength;
  final Duration delay;
  bool redirectsConfigured = false;
  int requests = 0;
  _ModelClient({this.statusCode = 200, this.empty = false, this.nullContentLength = false, this.delay = Duration.zero});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests++;
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    redirectsConfigured = request.followRedirects && request.maxRedirects >= 10;
    final length = empty ? 0 : 1;
    return http.StreamedResponse(
      Stream<List<int>>.value(empty ? const [] : [1]),
      statusCode,
      contentLength: nullContentLength ? null : length,
      request: request,
    );
  }
}

class _RangeClient extends http.BaseClient {
  final bool ignoreRange;
  final bool cutFirstRequest;
  final List<String> ranges = [];
  int encoderRequests = 0;

  _RangeClient({this.ignoreRange = false, this.cutFirstRequest = false});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final name = request.url.pathSegments.last;
    final range = request.headers['Range'];
    if (range != null) ranges.add(range);
    if (name != 'encoder.onnx') {
      return http.StreamedResponse(
        Stream<List<int>>.value([1]),
        200,
        contentLength: 1,
        request: request,
      );
    }
    encoderRequests++;
    if (cutFirstRequest && encoderRequests == 1) {
      return http.StreamedResponse(
        _cutStream(),
        200,
        contentLength: 100,
        request: request,
      );
    }
    if (range != null && !ignoreRange) {
      return http.StreamedResponse(
        Stream<List<int>>.value(List<int>.filled(50, 2)),
        206,
        contentLength: 50,
        headers: const {'content-range': 'bytes 50-99/100'},
        request: request,
      );
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(List<int>.filled(100, 3)),
      200,
      contentLength: 100,
      request: request,
    );
  }

  Stream<List<int>> _cutStream() async* {
    yield List<int>.filled(50, 1);
    throw http.ClientException('connection closed');
  }
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('model-manager-test-');
  });

  tearDown(() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  });

  Map<String, int> sizes() => {
        'encoder.onnx': 1,
        'decoder.onnx': 1,
        'joiner.onnx': 1,
        'tokens.txt': 1,
      };

  test('downloads all real model files and marks installation complete', () async {
    final client = _ModelClient();
    final manager = ModelManager(
      client: client,
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await manager.download();
    expect(await manager.isInstalled(), isTrue);
    expect(client.redirectsConfigured, isTrue);
    expect(File('${directory.path}/encoder.onnx.part').existsSync(), isFalse);
    manager.dispose();
  });

  test('reports the exact file on HTTP 404 and removes part files', () async {
    final manager = ModelManager(
      client: _ModelClient(statusCode: 404),
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await expectLater(
      manager.download(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('encoder.onnx (404)'),
        ),
      ),
    );
    expect(File('${directory.path}/encoder.onnx.part').existsSync(), isFalse);
    manager.dispose();
  });

  test('rejects an empty downloaded file', () async {
    final manager = ModelManager(
      client: _ModelClient(empty: true),
      directoryProvider: () async => directory,
      minimumSizes: {...sizes(), 'encoder.onnx': 2},
    );
    await expectLater(
      manager.download(),
      throwsA(
        isA<Exception>().having(
          (error) => error.toString(),
          'message',
          contains('encoder.onnx'),
        ),
      ),
    );
    manager.dispose();
  });

  test('coalesces concurrent installation requests', () async {
    final client = _ModelClient(delay: const Duration(milliseconds: 5));
    final manager = ModelManager(
      client: client,
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await Future.wait([
      manager.installModel(),
      manager.installModel(),
      manager.installModel(),
    ]);
    expect(client.requests, 4);
    expect(await manager.isInstalled(), isTrue);
    manager.dispose();
  });

  test('resumes a partial file with Range and Content-Range', () async {
    await File('${directory.path}/encoder.onnx.part').writeAsBytes(List<int>.filled(50, 1));
    final client = _RangeClient();
    final manager = ModelManager(
      client: client,
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await manager.installModel();
    expect(client.ranges, contains('bytes=50-'));
    expect(await File('${directory.path}/encoder.onnx').length(), 100);
    manager.dispose();
  });

  test('restarts safely when a server ignores Range with 200', () async {
    await File('${directory.path}/encoder.onnx.part').writeAsBytes(List<int>.filled(50, 9));
    final manager = ModelManager(
      client: _RangeClient(ignoreRange: true),
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await manager.installModel();
    expect(await File('${directory.path}/encoder.onnx').length(), 100);
    manager.dispose();
  });

  test('keeps a partial file after a transient connection failure', () async {
    final client = _RangeClient(cutFirstRequest: true);
    final manager = ModelManager(
      client: client,
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await manager.installModel();
    expect(client.ranges, isNotEmpty);
    expect(await manager.isInstalled(), isTrue);
    manager.dispose();
  });

  test('accepts tokens with unknown Content-Length and completes at EOF', () async {
    for (final name in ['encoder.onnx', 'decoder.onnx', 'joiner.onnx']) {
      await File('${directory.path}/$name').writeAsBytes([1]);
    }
    final progress = <ModelInstallProgress>[];
    final manager = ModelManager(
      client: _ModelClient(nullContentLength: true),
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await manager.installModel(onProgress: progress.add);
    expect(await manager.isInstalled(), isTrue);
    expect(await File('${directory.path}/tokens.txt').readAsBytes(), [1]);
    expect(File('${directory.path}/tokens.txt.part').existsSync(), isFalse);
    final tokenProgress = progress.where((item) => item.fileName == 'tokens.txt');
    expect(tokenProgress, isNotEmpty);
    expect(tokenProgress.every((item) => item.fileFraction == null), isTrue);
    expect(progress.where((item) => item.overallFraction != null).every((item) => item.overallFraction! <= 1), isTrue);
    manager.dispose();
  });

  test('truncates an inconsistent tokens part when server returns 200', () async {
    for (final name in ['encoder.onnx', 'decoder.onnx', 'joiner.onnx']) {
      await File('${directory.path}/$name').writeAsBytes([1]);
    }
    await File('${directory.path}/tokens.txt.part').writeAsBytes([9, 9, 9, 9]);
    final manager = ModelManager(
      client: _ModelClient(nullContentLength: true),
      directoryProvider: () async => directory,
      minimumSizes: sizes(),
    );
    await manager.installModel();
    expect(await File('${directory.path}/tokens.txt').readAsBytes(), [1]);
    expect(File('${directory.path}/tokens.txt.part').existsSync(), isFalse);
    manager.dispose();
  });
}
