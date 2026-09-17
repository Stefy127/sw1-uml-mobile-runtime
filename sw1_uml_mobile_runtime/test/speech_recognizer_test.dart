import 'package:flutter_test/flutter_test.dart';
import 'package:sw1_uml_mobile_runtime/features/speech/speech_recognizer_engine.dart';

class _FakeSpeechEngine implements SpeechRecognizerEngine {
  bool available = true;
  bool listening = false;
  String? recognizedText;

  @override bool get isAvailable => available;
  @override bool get isListening => listening;
  @override Future<void> initialize() async {}

  @override
  Future<void> startListening({required void Function(String text) onText}) async {
    if (!available) throw StateError('engine unavailable');
    listening = true;
    recognizedText = 'registrame una persona llamada Voz Sin Internet';
    onText(recognizedText!);
  }

  @override
  Future<void> stopListening() async => listening = false;

  @override
  Future<void> dispose() async => listening = false;
}

void main() {
  test('recognized text is delivered through the engine contract', () async {
    final engine = _FakeSpeechEngine();
    String? controllerText;
    await engine.initialize();
    await engine.startListening(onText: (text) => controllerText = text);
    expect(controllerText, 'registrame una persona llamada Voz Sin Internet');
    expect(engine.isListening, isTrue);
    await engine.stopListening();
    expect(engine.isListening, isFalse);
  });

  test('unavailable engine reports an initialization error', () async {
    final engine = _FakeSpeechEngine()..available = false;
    expect(
      engine.startListening(onText: (_) {}),
      throwsA(isA<StateError>()),
    );
  });
}
