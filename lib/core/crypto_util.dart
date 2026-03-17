import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:hex/hex.dart';
import 'dart:math';
import 'dart:typed_data';
import 'package:bech32/bech32.dart';
import 'package:uuid/uuid.dart';

/// 加密与加密算法工具类
/// 包含钱包助记词加解密、Ed25519 签名验证、Bech32 地址转换以及事件规范化逻辑
class CryptoUtil {
  /// 生成随机的 32 字节种子 (Seed)
  static Uint8List generateSeed() {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(32, (i) => random.nextInt(256)),
    );
  }

  /// 将用户密码转换为 AES 加密所需的 256 位密钥 (SHA-256)
  static Uint8List _passwordToAesKey(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }

  /// 使用密码加密钱包种子
  /// 采用 AES-256-CBC 模式，并在结果中包含 16 字节的随机 IV
  static String encryptSeed(Uint8List seed, String password) {
    final aesKey = _passwordToAesKey(password);
    final key = enc.Key(aesKey);
    final randomIvBytes = Uint8List.fromList(
      List<int>.generate(16, (i) => Random.secure().nextInt(256)),
    );
    final dynamicIv = enc.IV(randomIvBytes);
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
    final encrypted = encrypter.encryptBytes(seed, iv: dynamicIv);

    // 组合 IV (16字节) + 密文
    final combined = Uint8List(16 + encrypted.bytes.length);
    combined.setRange(0, 16, dynamicIv.bytes);
    combined.setRange(16, combined.length, encrypted.bytes);
    return base64Encode(combined);
  }

  /// 使用密码解密钱包种子
  static Uint8List? decryptSeed(String encryptedBase64, String password) {
    try {
      final aesKey = _passwordToAesKey(password);
      final key = enc.Key(aesKey);
      final combined = base64Decode(encryptedBase64);
      if (combined.length < 16) return null;

      final iv = enc.IV(combined.sublist(0, 16));
      final ciphertextBytes = combined.sublist(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final decrypted = encrypter.decryptBytes(
        enc.Encrypted(ciphertextBytes),
        iv: iv,
      );
      return Uint8List.fromList(decrypted);
    } catch (e) {
      return null; // 密码错误或数据损坏
    }
  }

  /// 从种子推导出 Ed25519 密钥对
  static ed.KeyPair deriveKeyPair(Uint8List seed) {
    final privateKey = ed.newKeyFromSeed(seed);
    return ed.KeyPair(privateKey, ed.public(privateKey));
  }

  /// 获取 Agent ID (公钥的 Hex 字符串)
  static String getAgentId(ed.KeyPair keyPair) {
    return HEX.encode(keyPair.publicKey.bytes);
  }

  /// 将 Hex 格式的 Agent ID 转换为 Bech32 地址 (以 agent 开头)
  static String getAgentAddress(String agentIdHex) {
    final bytes = HEX.decode(agentIdHex);
    final converted = _convertBits(bytes, 8, 5, true);
    const bech32Codec = Bech32Codec();
    return bech32Codec.encode(Bech32('agent', converted));
  }

  /// Bech32 编码所需的位转换工具函数
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

  /// 实现与 Python json.dumps(sort_keys=True, separators=(',', ':')) 完全一致的序列化
  /// 保证在不同语言环境下计算出的哈希值一致
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

  /// 计算字符串的 SHA-256 哈希值
  static String computeHash(String input) {
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// 构造事件待签名负载 (Canonical Payload)
  /// 规则：id|from|chat_id|chat_type|kind|created_at|content_hash|ext_hash
  static String canonicalEventPayload(Map<String, dynamic> event) {
    final contentHash = computeHash(event['content'] as String);
    final chat = event['chat'] as Map<String, dynamic>;

    // 构造扩展字段，默认值与协议一致
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

  /// 使用私钥对负载进行 Ed25519 签名，返回 Base64 字符串
  static String signB64(ed.PrivateKey privateKey, String payload) {
    final signature = ed.sign(privateKey, utf8.encode(payload) as Uint8List);
    return base64Encode(signature);
  }

  /// 构造 Chat 会话对象
  /// 如果是 DM (私聊)，会自动根据 AgentID 排序生成唯一的 ChatID
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

  /// 构造一个完整的 Event 对象结构
  static Map<String, dynamic> buildEvent({
    required String agentId,
    required Map<String, dynamic> chat,
    required String kind,
    required String content,
    Map<String, dynamic>? metadata,
    String contentType = "text/plain",
    List<Map<String, dynamic>>? attachments,
  }) {
    final event = {
      "id": const Uuid().v4(),
      "from": agentId,
      "chat": chat,
      "kind": kind,
      "created_at": DateTime.now().millisecondsSinceEpoch ~/ 1000,
      "content": content,
      "content_type": contentType,
    };
    if (attachments != null && attachments.isNotEmpty) {
      event["attachments"] = attachments;
    }
    if (metadata != null && metadata.isNotEmpty) {
      event["metadata"] = metadata;
    }
    return event;
  }

  /// 验证 Ed25519 签名是否合法
  static bool verifySignature(
    String payload,
    String? sigB64,
    String publicKeyHex,
  ) {
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
