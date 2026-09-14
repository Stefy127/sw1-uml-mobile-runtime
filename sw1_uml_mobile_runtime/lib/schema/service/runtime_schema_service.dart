import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/api/api_config.dart';
import '../model/runtime_schema.dart';

class RuntimeSchemaService {
  Future<RuntimeSchema> load() async {
    final response = await http.get(
      Uri.parse('${ApiConfig.baseUrl}/api/runtime-schema'),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'No se pudo cargar runtime-schema. Código: ${response.statusCode}',
      );
    }

    final json = jsonDecode(response.body);

    return RuntimeSchema.fromJson(
      Map<String, dynamic>.from(json),
    );
  }
}