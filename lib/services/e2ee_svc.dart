// import 'dart:convert';
// import 'dart:typed_data';
// import 'package:device_info_plus/device_info_plus.dart';
// import 'package:webcrypto/webcrypto.dart';

// Future<JsonWebKeyPair> generateKeys() async {
//   final keyPair = await EcdhPrivateKey.generateKey(EllipticCurve.p256);
//   final publicKeyJwk = await keyPair.publicKey.exportJsonWebKey();
//   final privateKeyJwk = await keyPair.privateKey.exportJsonWebKey();

//   return JsonWebKeyPair(
//     privateKey: json.encode(privateKeyJwk),
//     publicKey: json.encode(publicKeyJwk),
//   );
// }

// // Model class for storing keys
// class JsonWebKeyPair {
//   const JsonWebKeyPair({required this.privateKey, required this.publicKey});

//   final String privateKey;
//   final String publicKey;
// }

// // SendersJwk -> sender.privateKey
// // ReceiverJwk -> receiver.publicKey
// Future<List<int>> deriveKey(String senderJwk, String receiverJwk) async {
//   // Sender's key
//   final senderPrivateKey = json.decode(senderJwk);
//   final senderEcdhKey = await EcdhPrivateKey.importJsonWebKey(
//     senderPrivateKey,
//     EllipticCurve.p256,
//   );

//   // Receiver's key
//   final receiverPublicKey = json.decode(receiverJwk);
//   final receiverEcdhKey = await EcdhPublicKey.importJsonWebKey(
//     receiverPublicKey,
//     EllipticCurve.p256,
//   );

//   // Generating CryptoKey
//   final derivedBits = await senderEcdhKey.deriveBits(256, receiverEcdhKey);
//   return derivedBits;
// }

// // The "iv" stands for initialization vector (IV). To ensure the encryption’s strength,
// // each encryption process must use a random and distinct IV.
// // It’s included in the message so that the decryption procedure can use it.
// final Uint8List iv = Uint8List.fromList('Initialization Vector'.codeUnits);

// Future<String> encryptMessage(String message, List<int> deriveKey) async {
//   // Importing cryptoKey
//   final aesGcmSecretKey = await AesGcmSecretKey.importRawKey(deriveKey);

//   // Converting message into bytes
//   final messageBytes = Uint8List.fromList(message.codeUnits);

//   // Encrypting the message
//   final encryptedMessageBytes = await aesGcmSecretKey.encryptBytes(
//     messageBytes,
//     iv,
//   );

//   // Converting encrypted message into String
//   final encryptedMessage = String.fromCharCodes(encryptedMessageBytes);
//   return encryptedMessage;
// }

// Future<String> decryptMessage(
//   String encryptedMessage,
//   List<int> deriveKey,
// ) async {
//   // Importing cryptoKey
//   final aesGcmSecretKey = await AesGcmSecretKey.importRawKey(deriveKey);

//   // Converting message into bytes
//   final messageBytes = Uint8List.fromList(encryptedMessage.codeUnits);

//   // Decrypting the message
//   final decryptedMessageBytes = await aesGcmSecretKey.decryptBytes(
//     messageBytes,
//     iv,
//   );

//   // Converting decrypted message into String
//   final decryptedMessage = String.fromCharCodes(decryptedMessageBytes);
//   return decryptedMessage;
// }

// class User {
//   final String name;
//   final String privateKey;
//   final String publicKey;

//   User({required this.name, required this.privateKey, required this.publicKey});
// }

// class db_entry {
//   final String time;
//   final String sender;
//   final String content;

//   db_entry({required this.time, required this.sender, required this.content});
// }

// class dummy_database {
//   // time, sender and content
//   static List<db_entry> messages = [];
//   void add(db_entry entry) {
//     messages.add(entry);
//   }

//   // getter for messages
//   List<db_entry> get getMessages => messages;
// }

// void main() async {
//   // Generating keyPair using the function defined in above steps
//   final keyPair = await generateKeys();
//   // print("privateKey: ${keyPair.privateKey}");
//   // print("publicKey: ${keyPair.publicKey}");
//   final decoded = json.decode(keyPair.privateKey);
//   // print("decoded: $decoded");
//   final keyPair1 = await generateKeys();
//   final keyPair2 = await generateKeys();

//   final user1 = User(
//     name: "Regulu",
//     privateKey: keyPair1.privateKey,
//     publicKey: keyPair1.publicKey,
//   );
//   final user2 = User(
//     name: "Peter",
//     privateKey: keyPair2.privateKey,
//     publicKey: keyPair2.publicKey,
//   );

//   final database = dummy_database();
//   database.add(
//     db_entry(
//       time: DateTime.now().toString(),
//       sender: user1.name,
//       content: await encryptMessage(
//         "Hello, ${user2.name}!",
//         await deriveKey(user1.privateKey, user2.publicKey),
//       ),
//     ),
//   );

//   final encryptedMessage = database.getMessages[0].content;
//   print("Encrypted message: ${encryptedMessage}");

//   final decryptedMessage = await decryptMessage(
//     encryptedMessage,
//     await deriveKey(user1.privateKey, user2.publicKey),
//   );
//   print("Decrypted message: ${decryptedMessage}");
// }
