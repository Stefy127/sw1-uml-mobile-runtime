class CommandTextNormalizer {
  static String normalize(String value) {
    const accents = 'áéíóúüñÁÉÍÓÚÜÑ';
    const plain = 'aeiouunAEIOUUN';
    var result = value.toLowerCase();
    result = result
        .replaceAll('á', 'a')
        .replaceAll('é', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ü', 'u')
        .replaceAll('ñ', 'n');
    for (var i = 0; i < accents.length; i++) {
      result = result.replaceAll(accents[i], plain[i].toLowerCase());
    }
    result = result.replaceAll(RegExp(r'[^a-z0-9._-]+'), ' ').trim();
    return result.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String singular(String value) {
    if (value.endsWith('es') && value.length > 3) return value.substring(0, value.length - 2);
    if (value.endsWith('s') && value.length > 2) return value.substring(0, value.length - 1);
    return value;
  }
}
