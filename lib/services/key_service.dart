import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class KeyService {
  static const _storage = FlutterSecureStorage();
  static const _privateKeyStorageKey = 'device_x25519_private_key';
  static const _publicKeyStorageKey = 'device_x25519_public_key';

  final _algorithm = X25519();

  Future<String> generateAndSaveDeviceKeys() async {
    // 1. Generate new X25519 Key Pair
    final SimpleKeyPair keyPair = await _algorithm.newKeyPair();

    // 2. Extract raw bytes for Private Key
    final SimpleKeyPairData keyPairData = await keyPair.extract();
    final List<int> privateKeyBytes = keyPairData.bytes;

    // 3. Extract Public Key and cast to SimplePublicKey to access .bytes
    final PublicKey publicKey = await keyPair.extractPublicKey();
    final SimplePublicKey simplePublicKey = publicKey as SimplePublicKey;
    final List<int> publicKeyBytes = simplePublicKey.bytes;

    // 4. Encode keys to Base64 strings
    final String base64PrivateKey = base64Encode(privateKeyBytes);
    final String base64PublicKey = base64Encode(publicKeyBytes);

    // 5. Save Private Key to Secure Storage
    await _storage.write(key: _privateKeyStorageKey, value: base64PrivateKey);
    await _storage.write(key: _publicKeyStorageKey, value: base64PublicKey);

    return base64PublicKey;
  }

  /// Load the local private key from secure storage
  Future<SimpleKeyPair?> getPrivateKey() async {
    final String? base64PrivateKey = await _storage.read(
      key: _privateKeyStorageKey,
    );
    final String? base64PublicKey = await _storage.read(
      key: _publicKeyStorageKey,
    );
    if (base64PrivateKey == null) return null;

    final List<int> privateKeyBytes = base64Decode(base64PrivateKey);
    final List<int> publicKeyBytes = base64Decode(base64PublicKey!);

    // Reconstruct KeyPair from raw stored bytes
    return SimpleKeyPairData(
      privateKeyBytes,
      publicKey: SimplePublicKey(publicKeyBytes, type: KeyPairType.x25519),
      type: KeyPairType.x25519,
    );
  }
}
