import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class TemplatesDb {
  static const String _databaseName = 'templates.db';
  static const int _databaseVersion = 2; // Incremented for user_id migration
  static const String _tableTemplates = 'workout_templates';
  static const String _tableExercises = 'template_exercises';
  static const String _tableSets = 'template_sets';

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
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // Workout templates table
    await db.execute('''
      CREATE TABLE $_tableTemplates (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id TEXT UNIQUE NOT NULL,
        user_id TEXT NOT NULL,
        name TEXT NOT NULL,
        description TEXT,
        created_at INTEGER NOT NULL,
        last_used_at INTEGER
      )
    ''');

    // Create index for user_id
    await db.execute('''
      CREATE INDEX idx_templates_user_id ON $_tableTemplates(user_id)
    ''');

    // Template exercises table
    await db.execute('''
      CREATE TABLE $_tableExercises (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_id TEXT NOT NULL,
        exercise_id TEXT NOT NULL,
        exercise_name TEXT NOT NULL,
        order_index INTEGER NOT NULL,
        FOREIGN KEY (template_id) REFERENCES $_tableTemplates(template_id) ON DELETE CASCADE
      )
    ''');

    // Template sets table
    await db.execute('''
      CREATE TABLE $_tableSets (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        template_exercise_id INTEGER NOT NULL,
        target_reps INTEGER,
        target_weight REAL,
        order_index INTEGER NOT NULL,
        FOREIGN KEY (template_exercise_id) REFERENCES $_tableExercises(id) ON DELETE CASCADE
      )
    ''');

    // Create indexes
    await db.execute('''
      CREATE INDEX idx_template_exercises_template_id ON $_tableExercises(template_id)
    ''');
    await db.execute('''
      CREATE INDEX idx_template_sets_exercise_id ON $_tableSets(template_exercise_id)
    ''');
  }

  static Future<void> _onUpgrade(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      // Add user_id column to existing templates table
      await db.execute('''
        ALTER TABLE $_tableTemplates ADD COLUMN user_id TEXT
      ''');

      // Create index for user_id
      await db.execute('''
        CREATE INDEX idx_templates_user_id ON $_tableTemplates(user_id)
      ''');

      // Set user_id to empty string for existing templates (they will be orphaned)
      // This is safe because we'll filter by user_id going forward
      await db.execute('''
        UPDATE $_tableTemplates SET user_id = '' WHERE user_id IS NULL
      ''');
    }
  }

  static Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }
}
