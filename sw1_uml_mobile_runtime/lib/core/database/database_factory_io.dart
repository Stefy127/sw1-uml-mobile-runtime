import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

Future<Database> openRuntimeDatabase(String name) async {
  final directory = await getApplicationSupportDirectory();
  final databasePath = p.join(directory.path, name);
  return databaseFactoryIo.openDatabase(databasePath);
}
