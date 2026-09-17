import 'package:speech_to_text/speech_to_text.dart';
import 'speech_recognizer_engine.dart';

class SystemSpeechRecognizerAdapter implements SpeechRecognizerEngine {
  final SpeechToText _speech = SpeechToText();
  bool _available = false;
  bool _listening = false;

  @override bool get isAvailable => _available;
  @override bool get isListening => _listening;

  @override
  Future<void> initialize() async {
    _available = await _speech.initialize();
    if (!_available) throw Exception('El reconocimiento del sistema no está disponible.');
  }

  @override
  Future<void> startListening({required void Function(String text) onText}) async {
    if (!_available) await initialize();
    _listening = true;
    await _speech.listen(
      listenOptions: SpeechListenOptions(localeId: 'es_BO', partialResults: true),
      onResult: (result) => onText(result.recognizedWords),
    );
  }

  @override
  Future<void> stopListening() async {
    _listening = false;
    await _speech.stop();
  }

  @override
  Future<void> dispose() async {
    await _speech.stop();
    _listening = false;
  }
}
