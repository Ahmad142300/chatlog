import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

// 1. Prefix FFI imports to avoid collisions
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

// 2. Hide colliding top-level functions from sqlcipher import
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;

class DatabaseService {
  // --- SINGLETON PATTERN SETUP ---
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();
  // -------------------------------

  cipher.Database? _database;
  static const _secureStorage = FlutterSecureStorage();
  static const _dbKeyStorageKey = 'db_passphrase';

  // Retrieve existing database instance or initialize a new encrypted instance
  Future<cipher.Database> get database async {
    if (_database != null && _database!.isOpen) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<cipher.Database> _initDatabase() async {
    // 1. Fetch or generate the database passphrase from Secure Storage
    String? dbKey = await _secureStorage.read(key: _dbKeyStorageKey);
    if (dbKey == null) {
      final secureRandom = Random.secure();
      final List<int> keyBytes = List<int>.generate(
        32,
        (_) => secureRandom.nextInt(256),
      );

      dbKey = base64Encode(keyBytes);
      await _secureStorage.write(key: _dbKeyStorageKey, value: dbKey);
    }

    // 2. Resolve database directory per platform
    String dbDir;
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      final docDir = await getApplicationSupportDirectory();
      dbDir = docDir.path;
    } else {
      dbDir = await cipher.getDatabasesPath();
    }

    final path = join(dbDir, 'app_database.db');

    // 3. Open database using Desktop FFI or Mobile native channels
    if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      ffi.sqfliteFfiInit();
      final factory = ffi.databaseFactoryFfi;

      // Desktop FFI uses OpenDatabaseOptions
      final db = await factory.openDatabase(
        path,
        options: ffi.OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await _executeSchema(db);
          },
          onOpen: (db) async {
            // Apply SQLCipher passphrase and enable Foreign Key constraints
            await db.execute("PRAGMA key = '$dbKey';");
            await db.execute("PRAGMA foreign_keys = ON;");
          },
        ),
      );
      return db as cipher.Database;
    } else {
      // Mobile native openDatabase accepts top-level 'password'
      return await cipher.openDatabase(
        path,
        password: dbKey,
        version: 1,
        onCreate: (db, version) async {
          await _executeSchema(db);
        },
        onOpen: (db) async {
          await db.execute("PRAGMA foreign_keys = ON;");
        },
      );
    }
  }

  /// Single schema execution method compatible with both Mobile and Desktop FFI database instances
  Future<void> _executeSchema(dynamic db) async {
    // 1. Devices Table
    await db.execute('''
      CREATE TABLE devices (
          device_id TEXT PRIMARY KEY,
          device_name TEXT NOT NULL,
          public_key TEXT NOT NULL,
          is_self INTEGER NOT NULL DEFAULT 0,
          created_at INTEGER NOT NULL
      );
    ''');

    // 2. Messages Table
    await db.execute('''
      CREATE TABLE messages (
          message_id TEXT PRIMARY KEY,
          sender_device_id TEXT NOT NULL,
          recipient_device_id TEXT,
          content_type TEXT NOT NULL, -- 'text', 'media', 'mixed'
          body TEXT,
          timestamp INTEGER NOT NULL,
          delivery_status TEXT NOT NULL,
          FOREIGN KEY (sender_device_id) REFERENCES devices(device_id)
      );
    ''');

    // 3. Attachments Table
    await db.execute('''
      CREATE TABLE attachments (
          attachment_id TEXT PRIMARY KEY,
          message_id TEXT NOT NULL,
          file_path TEXT NOT NULL,
          file_name TEXT NOT NULL,
          file_type TEXT NOT NULL, -- Extension or MIME type
          file_size INTEGER,       -- File size in bytes
          FOREIGN KEY (message_id) REFERENCES messages(message_id) ON DELETE CASCADE
      );
    ''');

    // 4. Indexes for Query Performance
    await db.execute(
      'CREATE INDEX idx_messages_timestamp ON messages(timestamp DESC);',
    );
    await db.execute(
      'CREATE INDEX idx_messages_sender ON messages(sender_device_id);',
    );
    await db.execute(
      'CREATE INDEX idx_attachments_message_id ON attachments(message_id);',
    );
  }

  /// Close connection cleanly (e.g. on logout or app reset)
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
    }
  }
}

Future<Directory> getAppMediaDirectory() async {
  final Directory baseDir =
      (Platform.isLinux || Platform.isMacOS || Platform.isWindows)
      ? await getApplicationSupportDirectory()
      : await getApplicationDocumentsDirectory();

  final Directory mediaDir = Directory(join(baseDir.path, 'media'));

  if (!await mediaDir.exists()) {
    await mediaDir.create(recursive: true);
  }

  return mediaDir;
}
