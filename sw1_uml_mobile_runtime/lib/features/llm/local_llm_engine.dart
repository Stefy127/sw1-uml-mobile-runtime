abstract class LocalLlmEngine {
  Future<void> initialize();
  Future<String> generate(String prompt);
  Future<String> generateChat({required String systemPrompt, required String userPrompt});
  Future<void> clearContext();
  Future<void> dispose();
  bool get isAvailable;
}
