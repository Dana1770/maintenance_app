import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DBHelper {
  static Database? _db;

  static Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDB();
    return _db!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), 'maintenance.db');
    return openDatabase(
      path,
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE users (
            id           INTEGER PRIMARY KEY AUTOINCREMENT,
            name         TEXT    NOT NULL,
            email        TEXT    NOT NULL UNIQUE,
            password     TEXT    NOT NULL,
            phone        TEXT    DEFAULT '',
            id_code      TEXT    DEFAULT '',
            photo_path   TEXT    DEFAULT '',
            server_url   TEXT    DEFAULT ''
          )
        ''');
      },
      onUpgrade: (db, old, _) async {
        if (old < 2) {
          await db.execute('ALTER TABLE users ADD COLUMN phone TEXT DEFAULT ""');
          await db.execute('ALTER TABLE users ADD COLUMN id_code TEXT DEFAULT ""');
        }
        if (old < 3) {
          await db.execute('ALTER TABLE users ADD COLUMN photo_path TEXT DEFAULT ""');
        }
        if (old < 4) {
          await db.execute('ALTER TABLE users ADD COLUMN server_url TEXT DEFAULT ""');
        }
      },
    );
  }

  // ── Register ──────────────────────────────────────────────────────────────
  static Future<String?> registerUser({
    required String name,
    required String email,
    required String password,
    String serverUrl = '',
  }) async {
    try {
      final db = await database;
      final prefix = name.length >= 2
          ? name.substring(0, 2).toUpperCase()
          : name.toUpperCase();
      final suffix =
      DateTime.now().millisecondsSinceEpoch.toString().substring(7);
      await db.insert('users', {
        'name'      : name,
        'email'     : email.toLowerCase().trim(),
        'password'  : password,
        'phone'     : '',
        'id_code'   : '#$prefix-$suffix',
        'photo_path': '',
        'server_url': serverUrl.trim(),
      }, conflictAlgorithm: ConflictAlgorithm.fail);
      return null;
    } catch (_) {
      return 'An account with this email already exists.';
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> loginUser({
    required String email,
    required String password,
  }) async {
    final db = await database;
    final r = await db.query('users',
        where: 'email = ? AND password = ?',
        whereArgs: [email.toLowerCase().trim(), password],
        limit: 1);
    return r.isEmpty ? null : r.first;
  }

  // ── Get by email ──────────────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getUserByEmail(String email) async {
    final db = await database;
    final r = await db.query('users',
        where: 'email = ?',
        whereArgs: [email.toLowerCase().trim()],
        limit: 1);
    return r.isEmpty ? null : r.first;
  }

  // ── Check email exists ────────────────────────────────────────────────────
  static Future<bool> emailExists(String email) async =>
      (await getUserByEmail(email)) != null;

  // ── Update profile ────────────────────────────────────────────────────────
  static Future<void> updateProfile({
    required String email,
    required String name,
    required String phone,
    required String photoPath,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {'name': name, 'phone': phone, 'photo_path': photoPath},
      where: 'email = ?',
      whereArgs: [email.toLowerCase().trim()],
    );
  }

  // ── Update server URL ─────────────────────────────────────────────────────
  static Future<void> updateServerUrl({
    required String email,
    required String serverUrl,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {'server_url': serverUrl.trim()},
      where: 'email = ?',
      whereArgs: [email.toLowerCase().trim()],
    );
  }

  // ── Update password ───────────────────────────────────────────────────────
  static Future<void> updatePassword({
    required String email,
    required String newPassword,
  }) async {
    final db = await database;
    await db.update(
      'users',
      {'password': newPassword},
      where: 'email = ?',
      whereArgs: [email.toLowerCase().trim()],
    );
  }
}