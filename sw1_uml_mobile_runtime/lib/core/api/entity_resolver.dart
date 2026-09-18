import '../../features/commands/text_normalizer.dart';
import '../../schema/model/runtime_schema.dart';
import '../../core/database/generic_repository.dart';

enum EntityResolutionStatus { resolved, notFound, ambiguous, invalid }

class EntityResolutionResult {
  final EntityResolutionStatus status;
  final Map<String, dynamic>? record;
  final List<Map<String, dynamic>> matches;
  final String message;

  const EntityResolutionResult({
    required this.status,
    this.record,
    this.matches = const [],
    this.message = '',
  });
}

class EntityResolver {
  final GenericRepository repository;

  EntityResolver({GenericRepository? repository})
      : repository = repository ?? GenericRepository();

  Future<EntityResolutionResult> resolve(
    RuntimeEntity entity,
    Map<String, dynamic> selector,
  ) async {
    if (entity.name.trim().isEmpty) {
      return const EntityResolutionResult(
        status: EntityResolutionStatus.invalid,
        message: 'Entidad inválida.',
      );
    }
    if (selector.isEmpty) {
      return const EntityResolutionResult(
        status: EntityResolutionStatus.notFound,
        message: 'No se indicó selector.',
      );
    }

    final records = await repository.getAll(entity);
    final exactMatches = <Map<String, dynamic>>[];
    final containsMatches = <Map<String, dynamic>>[];

    for (final record in records) {
      var exact = false;
      var contains = false;
      for (final entry in selector.entries) {
        final key = entry.key.toString();
        final expected = entry.value;
        final actual = record[key] ?? record[key.toLowerCase()] ?? record[entry.key];
        if (_matchesExact(actual, expected)) {
          exact = true;
        } else if (_matchesContains(actual, expected)) {
          contains = true;
        }
      }
      if (exact) exactMatches.add(record);
      else if (contains) containsMatches.add(record);
    }

    if (exactMatches.length == 1) {
      return EntityResolutionResult(
        status: EntityResolutionStatus.resolved,
        record: exactMatches.first,
        matches: exactMatches,
        message: 'Registro resuelto por selector exacto.',
      );
    }
    if (exactMatches.length > 1) {
      return EntityResolutionResult(
        status: EntityResolutionStatus.ambiguous,
        matches: exactMatches,
        message: 'Hay varias coincidencias para ese selector.',
      );
    }
    if (containsMatches.length == 1) {
      return EntityResolutionResult(
        status: EntityResolutionStatus.resolved,
        record: containsMatches.first,
        matches: containsMatches,
        message: 'Registro resuelto por coincidencia parcial.',
      );
    }
    if (containsMatches.length > 1) {
      return EntityResolutionResult(
        status: EntityResolutionStatus.ambiguous,
        matches: containsMatches,
        message: 'Hay varias coincidencias parciales.',
      );
    }

    return const EntityResolutionResult(
      status: EntityResolutionStatus.notFound,
      message: 'No se encontró ningún registro coincidente.',
    );
  }

  Future<EntityResolutionResult> resolveText(
    RuntimeEntity entity,
    String text,
  ) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const EntityResolutionResult(
        status: EntityResolutionStatus.notFound,
        message: 'Texto vacío.',
      );
    }

    final fields = entity.fields
        .where((field) => !field.readOnly && !field.collection && field.type == 'string')
        .map((field) => field.name)
        .toList();

    final key = fields.contains(entity.displayField)
        ? entity.displayField
        : fields.isNotEmpty
            ? fields.first
            : entity.idField;

    return resolve(entity, {key: normalized});
  }

  bool _matchesExact(dynamic actual, dynamic expected) {
    if (actual == null || expected == null) return false;
    final actualText = _normalize(actual.toString());
    final expectedText = _normalize(expected.toString());
    return actualText == expectedText;
  }

  bool _matchesContains(dynamic actual, dynamic expected) {
    if (actual == null || expected == null) return false;
    final actualText = _normalize(actual.toString());
    final expectedText = _normalize(expected.toString());
    return expectedText.isNotEmpty && actualText.contains(expectedText);
  }

  String _normalize(String value) => CommandTextNormalizer.normalize(value.trim());
}
