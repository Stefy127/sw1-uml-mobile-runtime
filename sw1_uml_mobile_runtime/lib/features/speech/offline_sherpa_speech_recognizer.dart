import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'model_manager.dart';
import 'speech_recognizer_engine.dart';

class OfflineSherpaSpeechRecognizer implements SpeechRecognizerEngine {
  final ModelManager modelManager;
  final AudioRecorder _recorder = AudioRecorder();
  sherpa.OnlineRecognizer? _recognizer;
  sherpa.OnlineStream? _stream;
  StreamSubscription<Uint8List>? _subscription;
  bool _available = false;
  bool _listening = false;

  OfflineSherpaSpeechRecognizer({ModelManager? modelManager}) : modelManager = modelManager ?? ModelManager();

  @override bool get isAvailable => _available;
  @override bool get isListening => _listening;

  @override
  Future<void> initialize() async {
    final files = await modelManager.files();
    await sherpa.initBindingsAsync();
    final model = sherpa.OnlineModelConfig(
      transducer: sherpa.OnlineTransducerModelConfig(encoder: files.encoder, decoder: files.decoder, joiner: files.joiner),
      tokens: files.tokens,
      modelType: 'zipformer2',
    );
    _recognizer = sherpa.OnlineRecognizer(sherpa.OnlineRecognizerConfig(model: model, ruleFsts: ''));
    _available = true;
  }

  @override
  Future<void> startListening({required void Function(String text) onText}) async {
    if (!_available || _recognizer == null) await initialize();
    if (!await _recorder.hasPermission()) throw Exception('No se concedió permiso para usar el micrófono.');
    _stream = _recognizer!.createStream();
    final audio = await _recorder.startStream(const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1));
    _listening = true;
    _subscription = audio.listen((bytes) {
      if (!_listening || _stream == null) return;
      final samples = _pcm16ToFloat32(bytes);
      _stream!.acceptWaveform(samples: samples, sampleRate: 16000);
      while (_recognizer!.isReady(_stream!)) _recognizer!.decode(_stream!);
      final text = _recognizer!.getResult(_stream!).text;
      if (text.isNotEmpty) onText(text);
    });
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    await _subscription?.cancel();
    _subscription = null;
    await _recorder.stop();
    _stream?.free();
    _stream = null;
  }

  Float32List _pcm16ToFloat32(Uint8List bytes) {
    final result = Float32List(bytes.length ~/ 2);
    final data = ByteData.sublistView(bytes);
    for (var index = 0; index < result.length; index++) result[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
    return result;
  }

  @override
  Future<void> dispose() async {
    await stopListening();
    _recognizer?.free();
    _recognizer = null;
    _available = false;
    _recorder.dispose();
  }
}
