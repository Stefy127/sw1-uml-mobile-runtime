import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api/api_config.dart';
import '../model/entity_schema.dart';

class OpenApiSchemaService {
  Future<List<EntitySchema>> loadEntities() async {
    final response = await http.get(Uri.parse(ApiConfig.openApiUrl));

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo cargar OpenAPI. Código: ${response.statusCode}',
      );
    }

    final Map<String, dynamic> document = jsonDecode(response.body);

    final paths = document['paths'] as Map<String, dynamic>? ?? {};

    final entities = <EntitySchema>[];

    for (final path in paths.keys) {
      if (!path.startsWith('/api/')) {
        continue;
      }

      // Solo tomamos rutas base, no /{id}
      if (path.contains('{')) {
        continue;
      }

      final segment = path.replaceFirst('/api/', '');

      if (segment.isEmpty) {
        continue;
      }

      entities.add(
        EntitySchema(
          name: _formatName(segment),
          path: path,
        ),
      );
    }

    entities.sort((a, b) => a.name.compareTo(b.name));

    return entities;
  }

  String _formatName(String value) {
    if (value.isEmpty) {
      return value;
    }

    return '${value[0].toUpperCase()}${value.substring(1)}';
  }
}