// import 'package:flutter_secure_storage/flutter_secure_storage.dart';
// import 'package:uuid/uuid.dart';

// class DeviceIdentity {
//   // Singleton instance
//   static final DeviceIdentity _instance = DeviceIdentity._internal();
//   factory DeviceIdentity() => _instance;
//   DeviceIdentity._internal();

//   static const _storage = FlutterSecureStorage();
//   static const _keyDeviceId = 'local_device_id';

//   String? _cachedDeviceId;

//   /// Synchronous getter to fetch the ID instantly from RAM
//   String get deviceId {
//     if (_cachedDeviceId == null) {
//       throw StateError(
//         'DeviceIdentity must be initialized in main() before use.',
//       );
//     }
//     return _cachedDeviceId!;
//   }

//   /// Called ONCE inside main.dart during application boot
//   Future<void> initialize() async {
//     String? id = await _storage.read(key: _keyDeviceId);

//     if (id == null) {
//       // First boot: Generate a unique ID for this device and persist it
//       id = const Uuid().v4();
//       await _storage.write(key: _keyDeviceId, value: id);
//     }

//     _cachedDeviceId = id;
//   }
// }
