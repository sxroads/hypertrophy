import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class EventQueueDb {
  static const String _databaseName = 'event_queue.db';
  static const int _databaseVersion = 1;
  static const String _tableName = 'event_queue';

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
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id TEXT UNIQUE NOT NULL,
        event_type TEXT NOT NULL,
        payload TEXT NOT NULL,
        sequence_number INTEGER NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        retry_count INTEGER DEFAULT 0,
        status TEXT DEFAULT 'pending'
      )
    ''');

    // Create indexes for efficient querying
    await db.execute('''
      CREATE INDEX idx_event_queue_status ON $_tableName(status)
    ''');
    await db.execute('''
      CREATE INDEX idx_event_queue_sequence ON $_tableName(device_id, sequence_number)
    ''');
  }

  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
