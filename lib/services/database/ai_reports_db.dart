import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class AiReportsDb {
  static const String _databaseName = 'ai_reports.db';
  static const int _databaseVersion = 1;
  static const String _tableName = 'ai_reports';

  static Database? _database;

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _databaseName);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
        measurement_id TEXT PRIMARY KEY,
        report_text TEXT NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_ai_reports_created_at ON $_tableName(created_at)
    ''');
  }

  static Future<void> saveReport({
    required String measurementId,
    required String reportText,
  }) async {
    final db = await database;
    await db.insert(
      _tableName,
      {
        'measurement_id': measurementId,
        'report_text': reportText,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<Map<String, dynamic>?> getReport(String measurementId) async {
    final db = await database;
    final result = await db.query(
      _tableName,
      where: 'measurement_id = ?',
      whereArgs: [measurementId],
    );

    if (result.isEmpty) return null;

    return {
      'measurement_id': result.first['measurement_id'],
      'report_text': result.first['report_text'],
    };
  }

  static Future<void> deleteReport(String measurementId) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'measurement_id = ?',
      whereArgs: [measurementId],
    );
  }

  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}

