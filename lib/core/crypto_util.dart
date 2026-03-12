import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';

class CryptoUtil {
  /// Generates a random 32-byte seed (Equivalent to SigningKey.generate() in Python)
  static Uint8List generateSeed() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (i) => random.nextInt(256)));
  }

  /// Hashes the user password using SHA-256 to create a 32-byte AES key
  static Uint8List _passwordToAesKey(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  /// Encrypts the 32-byte seed using AES-CBC
  static String encryptSeed(Uint8List seed, String password) {
    final aesKey = _passwordToAesKey(password);
    final key = enc.Key(aesKey);
    final randomIvBytes = Uint8List.fromList(List<int>.generate(16, (i) => Random.secure().nextInt(256)));
    final dynamicIv = enc.IV(randomIvBytes);
    
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(seed, iv: dynamicIv);
    
    final combined = Uint8List(16 + encrypted.bytes.length);
    combined.setRange(0, 16, dynamicIv.bytes);
    combined.setRange(16, combined.length, encrypted.bytes);
    
    return base64Encode(combined);
  }

  /// Decrypts the 32-byte AES-encrypted seed using password
  static Uint8List? decryptSeed(String encryptedBase64, String password) {
    try {
      final aesKey = _passwordToAesKey(password);
      final key = enc.Key(aesKey);
      final combined = base64Decode(encryptedBase64);
      
      if (combined.length < 16) return null;
      
      final iv = enc.IV(combined.sublist(0, 16));
      final ciphertextBytes = combined.sublist(16);
      
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decryptBytes(enc.Encrypted(ciphertextBytes), iv: iv);
      return Uint8List.fromList(decrypted);
    } catch (e) {
      return null;
    }
  }

  /// Derives an ED25519 keypair from a 32-byte seed
  static ed.KeyPair deriveKeyPair(Uint8List seed) {
    final privateKey = ed.newKeyFromSeed(seed);
    return ed.KeyPair(privateKey, ed.public(privateKey));
  }

  /// Get Agent ID (Hex Public Key)
  static String getAgentId(ed.KeyPair keyPair) {
    return HEX.encode(keyPair.publicKey.bytes);
  }

  /// Get Private Key Hex (Hex Seed)
  static String getPrivateKeyHex(Uint8List seed) {
    return HEX.encode(seed);
  }

  /// Bech32 encoding for Agent Address (Matching Python's encode_public_key_bech32)
  /// Note: Assuming 'agent' as the prefix (hrp)
  static String getAgentAddress(String agentIdHex) {
    final bytes = HEX.decode(agentIdHex);
    // Convert 8-bit bytes to 5-bit groups for bech32
    final converted = _convertBits(bytes, 8, 5, true);
    const bech32Codec = Bech32Codec();
    return bech32Codec.encode(Bech32('agent', converted));
  }

  static List<int> _convertBits(List<int> data, int from, int to, bool pad) {
    int acc = 0;
    int bits = 0;
    List<int> result = [];
    int maxv = (1 << to) - 1;
    for (int value in data) {
      acc = (acc << from) | value;
      bits += from;
      while (bits >= to) {
        bits -= to;
        result.add((acc >> bits) & maxv);
      }
    }
    if (pad) {
      if (bits > 0) {
        result.add((acc << (to - bits)) & maxv);
      }
    }
    return result;
  }

  /// Hashes a message using SHA-256
  static Uint8List hashMessage(String message) {
    final bytes = utf8.encode(message);
    return Uint8List.fromList(sha256.convert(bytes).bytes);
  }

  /// Signs a hashed message with the private key
  static String signMessage(Uint8List messageHash, ed.PrivateKey privateKey) {
    final signature = ed.sign(privateKey, messageHash);
    return HEX.encode(signature);
  }

  static bool verifySignature(String message, String signatureHex, String publicKeyHex) {
    try {
      final messageHash = hashMessage(message);
      final signatureBytes = Uint8List.fromList(HEX.decode(signatureHex));
      final pubKeyBytes = Uint8List.fromList(HEX.decode(publicKeyHex));
      final pubKey = ed.PublicKey(pubKeyBytes);
      return ed.verify(pubKey, messageHash, signatureBytes);
    } catch (e) {
      return false;
    }
  }
}
