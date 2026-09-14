class LabelFormatter {
  static String fromField(String value) {
    if (value.isEmpty) return value;
    var result = value.replaceAll(RegExp(r'[_-]+'), ' ');
    result = result.replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m.group(1)} ${m.group(2)}');
    result = result.trim();
    if (result.toLowerCase().endsWith(' id')) {
      result = result.substring(0, result.length - 3).trim();
    }
    return result.isEmpty ? result : '${result[0].toUpperCase()}${result.substring(1)}';
  }
}
