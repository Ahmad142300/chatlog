import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:uuid/uuid.dart';
import 'key_service.dart';

class DeviceRegistrationService {
  // Singleton instance
  static final DeviceRegistrationService _instance =
      DeviceRegistrationService._internal();
  factory DeviceRegistrationService() => _instance;
  DeviceRegistrationService._internal();

  static const _secureStorage = FlutterSecureStorage();

  static const String _privateKeyStorageKey = 'device_x25519_private_key';
  static const String _deviceIDStorageKey = 'device_id';

  static String? _cachedDeviceId;

  /// Synchronous getter to fetch the active device ID instantly from RAM
  static String get deviceId {
    if (_cachedDeviceId == null) {
      throw StateError(
        'DeviceRegistrationService must be initialized or registered before reading deviceId.',
      );
    }
    return _cachedDeviceId!;
  }

  /// Called in main() on app boot to load existing device_id into RAM
  static Future<void> initialize() async {
    _cachedDeviceId = await _secureStorage.read(key: _deviceIDStorageKey);
  }

  /// Checks OS Secure Storage to determine if the device is new
  static Future<bool> isNewDevice() async {
    final String? privateKey = await _secureStorage.read(
      key: _privateKeyStorageKey,
    );
    return privateKey == null;
  }

  /// Registers the device, writes keys/UUID to storage, populates SQLCipher, and caches ID in RAM
  static Future<void> registerDevice(Database db) async {
    final KeyService keyService = KeyService();
    final String? publicKey = await keyService.generateAndSaveDeviceKeys();

    if (publicKey != null) {
      final String id = const Uuid().v4();

      // 1. Persist to Secure Storage
      await _secureStorage.write(key: _deviceIDStorageKey, value: id);

      // 2. Cache in RAM immediately
      _cachedDeviceId = id;

      // 3. Insert into SQLCipher devices table
      await db.insert('devices', {
        'device_id': id,
        'device_name': Platform.localHostname,
        'public_key': publicKey,
        'is_self': 1,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  /// Clears secure storage keys and resets RAM cache for quick debugging/resets
  static Future<void> clearDeviceRegistration() async {
    await _secureStorage.delete(key: _privateKeyStorageKey);
    await _secureStorage.delete(key: _deviceIDStorageKey);
    _cachedDeviceId = null;
  }
}
