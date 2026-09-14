import 'package:sembast/sembast.dart';
import 'database_factory.dart';

class LocalDatabase {
  static const databaseName = 'sw1_uml_mobile_runtime.db';
  static final _store = StoreRef<String, dynamic>.main();
  static Database? _database;

  static Future<Database> get instance async =>
      _database ??= await openRuntimeDatabase(databaseName);

  static Future<void> put(String key, dynamic value) async {
    final database = await instance;
    await _store.record(key).put(database, value);
  }

  static Future<dynamic> get(String key) async {
    final database = await instance;
    return _store.record(key).get(database);
  }
}
