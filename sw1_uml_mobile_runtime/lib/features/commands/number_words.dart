import 'text_normalizer.dart';

class SpanishNumberWords {
  static const _values = {
    'cero': 0, 'uno': 1, 'una': 1, 'dos': 2, 'tres': 3, 'cuatro': 4,
    'cinco': 5, 'seis': 6, 'siete': 7, 'ocho': 8, 'nueve': 9, 'diez': 10,
    'once': 11, 'doce': 12, 'trece': 13, 'catorce': 14, 'quince': 15,
    'dieciseis': 16, 'diecisiete': 17, 'dieciocho': 18, 'diecinueve': 19,
    'veinte': 20, 'veintiuno': 21, 'veintidos': 22, 'veintitres': 23,
    'veinticuatro': 24, 'veinticinco': 25, 'veintiseis': 26,
    'veintisiete': 27, 'veintiocho': 28, 'veintinueve': 29,
    'treinta': 30, 'cuarenta': 40, 'cincuenta': 50, 'sesenta': 60,
    'setenta': 70, 'ochenta': 80, 'noventa': 90, 'cien': 100,
  };

  static int? parse(String value) {
    final normalized = CommandTextNormalizer.normalize(value);
    final direct = _values[normalized];
    if (direct != null) return direct;
    final parts = normalized.split(' y ');
    if (parts.length == 2 && _values[parts[0]] != null && _values[parts[1]] != null && _values[parts[0]]! >= 20) {
      return _values[parts[0]]! + _values[parts[1]]!;
    }
    return null;
  }
}
