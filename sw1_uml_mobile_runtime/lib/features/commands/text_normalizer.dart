class CommandTextNormalizer {
  static String normalize(String value) {
    var result = value.toLowerCase();
    const replacements = {
      '\u00e1': 'a', '\u00e9': 'e', '\u00ed': 'i', '\u00f3': 'o',
      '\u00fa': 'u', '\u00fc': 'u', '\u00f1': 'n',
      '\u00c3\u00a1': 'a', '\u00c3\u00a9': 'e', '\u00c3\u00ad': 'i',
      '\u00c3\u00b3': 'o', '\u00c3\u00ba': 'u', '\u00c3\u00bc': 'u',
      '\u00c3\u00b1': 'n',
    };
    replacements.forEach((from, to) => result = result.replaceAll(from, to));
    result = result.replaceAll(RegExp(r'[^a-z0-9._-]+'), ' ').trim();
    return result.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String singular(String value) {
    if (value.endsWith('es') && value.length > 3) return value.substring(0, value.length - 2);
    if (value.endsWith('s') && value.length > 2) return value.substring(0, value.length - 1);
    return value;
  }
}
