class LlmInstallProgress {
  final int downloadedBytes;
  final int? totalBytes;

  const LlmInstallProgress(this.downloadedBytes, this.totalBytes);

  double? get fraction => totalBytes == null || totalBytes! <= 0
      ? null
      : (downloadedBytes / totalBytes!).clamp(0.0, 1.0);
}
