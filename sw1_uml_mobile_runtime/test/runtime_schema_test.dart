import 'package:flutter_test/flutter_test.dart';
import 'package:sw1_uml_mobile_runtime/core/formatters/label_formatter.dart';
import 'package:sw1_uml_mobile_runtime/schema/model/runtime_schema.dart';

void main() {
  test('parses runtime schema and finds entities', () {
    final schema = RuntimeSchema.fromJson({'schemaVersion': '1.0', 'application': 'Demo', 'version': '1', 'entities': [
      {'name': 'Paciente', 'endpoint': '/api/pacientes', 'idField': 'id', 'displayField': 'nombre', 'operations': {'list': true}, 'fields': [{'name': 'fechaNacimiento', 'type': 'date', 'editable': true}]}
    ]});
    expect(schema.schemaVersion, '1.0');
    expect(schema.entityByName('Paciente')!.displayField, 'nombre');
    expect(schema.entityByName('Otro'), isNull);
  });

  test('formats generic camelCase and separators', () {
    expect(LabelFormatter.fromField('carreraId'), 'Carrera');
    expect(LabelFormatter.fromField('fecha_nacimiento'), 'Fecha nacimiento');
    expect(LabelFormatter.fromField('sourceId'), 'Source');
  });
}
