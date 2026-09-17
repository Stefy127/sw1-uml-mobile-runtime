class SpeechModelNotInstalledException implements Exception {
  @override
  String toString() => 'El reconocimiento offline está disponible en Android/iOS.';
}

class SpeechModelFiles {
  final String encoder;
  final String decoder;
  final String joiner;
  final String tokens;
  const SpeechModelFiles({required this.encoder, required this.decoder, required this.joiner, required this.tokens});
}

class ModelInstallProgress {
  final String fileName;
  final int downloadedBytes;
  final int? totalBytes;
  final int overallDownloadedBytes;
  final int? overallTotalBytes;
  const ModelInstallProgress({required this.fileName, required this.downloadedBytes, required this.totalBytes, required this.overallDownloadedBytes, required this.overallTotalBytes});
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
  static const modelSize = 'aprox. 60 MB (cuatro archivos ONNX/texto)';
  bool get isInstalling => false;
  Future<bool> isInstalled() async => false;
  Future<SpeechModelFiles> files() async => throw SpeechModelNotInstalledException();
  Future<void> installModel({void Function(ModelInstallProgress progress)? onProgress, void Function(String status)? onStatus}) async => throw SpeechModelNotInstalledException();
  Future<void> download({void Function(ModelInstallProgress progress)? onProgress, void Function(String status)? onStatus}) => installModel(onProgress: onProgress, onStatus: onStatus);
}
