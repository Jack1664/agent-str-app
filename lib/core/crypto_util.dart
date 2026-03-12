import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';
import 'package:uuid/uuid.dart';

class CryptoUtil {
  static Uint8List generateSeed() {
    final random = Random.secure();
    return Uint8List.fromList(List<int>.generate(32, (i) => random.nextInt(256)));
  }

  static Uint8List _passwordToAesKey(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

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

  static ed.KeyPair deriveKeyPair(Uint8List seed) {
    final privateKey = ed.newKeyFromSeed(seed);
    return ed.KeyPair(privateKey, ed.public(privateKey));
  }

  static String getAgentId(ed.KeyPair keyPair) {
    return HEX.encode(keyPair.publicKey.bytes);
  }

  static String getAgentAddress(String agentIdHex) {
    final bytes = HEX.decode(agentIdHex);
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
    if (pad && bits > 0) {
      result.add((acc << (to - bits)) & maxv);
    }
    return result;
  }

  // Exact match for Python's json.dumps(sort_keys=True, separators=(',', ':'))
  static String _jsonDumps(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.toList()..sort();
      final List<String> parts = [];
      for (var key in sortedKeys) {
        parts.add("\"$key\":${_jsonDumps(value[key])}");
      }
      return "{${parts.join(",")}}";
    } else if (value is List) {
      return "[${value.map((e) => _jsonDumps(e)).join(",")}]";
    } else if (value is String) {
      return jsonEncode(value);
    } else if (value == null) {
      return "null";
    } else {
      return value.toString();
    }
  }

  static String computeHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  static String canonicalEventPayload(Map<String, dynamic> event) {
    final contentHash = computeHash(event['content'] as String);
    final chat = event['chat'] as Map<String, dynamic>;

    final ext = {
      "content_type": event['content_type'] ?? "text/plain",
      "attachments": event['attachments'] ?? [],
      "metadata": event['metadata'] ?? {},
    };

    final payloadParts = [
      event["id"],
      event["from"],
      chat["id"],
      chat["type"],
      event["kind"],
      event["created_at"].toString(),
      contentHash,
      computeHash(_jsonDumps(ext)),
    ];
    return payloadParts.join("|");
  }

  static String signB64(ed.PrivateKey privateKey, String payload) {
    final signature = ed.sign(privateKey, utf8.encode(payload) as Uint8List);
    return base64Encode(signature);
  }

  static Map<String, dynamic> buildChat({
    required String agentId,
    required String peerId,
    required String chatType,
  }) {
    if (chatType == "dm") {
      final List<String> agents = [agentId, peerId]..sort();
      final chatId = "dm:${agents[0]}:${agents[1]}";
      return {"id": chatId, "type": "dm"};
    }
    return {"id": "system:$agentId", "type": "system"};
  }

  static Map<String, dynamic> buildEvent({
    required String agentId,
    required Map<String, dynamic> chat,
    required String kind,
    required String content,
    Map<String, dynamic>? metadata,
  }) {
    final event = {
      "id": const Uuid().v4(),
      "from": agentId,
      "chat": chat,
      "kind": kind,
      "created_at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
      "content": content,
    };
    if (metadata != null && metadata.isNotEmpty) {
      event["metadata"] = metadata;
    }
    return event;
  }

  static bool verifySignature(String payload, String? sigB64, String publicKeyHex) {
    if (sigB64 == null) return false;
    try {
      final payloadBytes = utf8.encode(payload) as Uint8List;
      final signatureBytes = base64Decode(sigB64);
      final pubKeyBytes = Uint8List.fromList(HEX.decode(publicKeyHex));
      final pubKey = ed.PublicKey(pubKeyBytes);
      return ed.verify(pubKey, payloadBytes, signatureBytes);
    } catch (e) {
      return false;
    }
  }
}
