abstract class SpeechRecognizerEngine {
  bool get isAvailable;
  bool get isListening;
  Future<void> initialize();
  Future<void> startListening({required void Function(String text) onText});
  Future<void> stopListening();
  Future<void> dispose();
}
