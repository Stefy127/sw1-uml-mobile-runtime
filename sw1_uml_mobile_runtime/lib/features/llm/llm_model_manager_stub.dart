import 'llm_install_progress.dart';

class LlmModelManager {
  static const modelFileName = 'Qwen3-0.6B-Q4_K_M.gguf';
  static const modelUrl = 'https://huggingface.co/QuantFactory/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B.Q4_K_M.gguf?download=true';
  bool get isInstalling => false;
  Future<bool> isInstalled() async => false;
  Future<String> modelPath() async => throw StateError('LLM local no disponible en esta plataforma.');
  Future<void> installModel({void Function(LlmInstallProgress progress)? onProgress}) async =>
      throw StateError('LLM local no disponible en esta plataforma.');
  void dispose() {}
}
