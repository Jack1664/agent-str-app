import '../core/crypto_util.dart';

class Wallet {
  final String id;
  String name;
  final String seedHex; // 存储原始私钥种子 (Hex格式)
  final String agentId; // Public Key Hex
  final String agentAddress; // Bech32 Address

  Wallet({
    required this.id,
    required this.name,
    required this.seedHex,
    required this.agentId,
    required this.agentAddress,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'seedHex': seedHex,
      'agentId': agentId,
      'agentAddress': agentAddress,
    };
  }

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String? ?? '';
    final String name = json['name'] as String? ?? 'Unnamed Wallet';

    // 兼容旧字段 encryptedBase64Seed，如果存在则视为明文(因为现在全局去掉了加密)
    // 或者在 Provider 加载时进行转换。这里暂时简单处理。
    final String seedHex = json['seedHex'] as String? ?? json['encryptedBase64Seed'] as String? ?? '';

    final String agentId = json['agentId'] as String? ?? json['publicKeyHex'] as String? ?? '';

    String agentAddress = json['agentAddress'] as String? ?? '';
    if (agentAddress.isEmpty && agentId.isNotEmpty) {
      try {
        agentAddress = CryptoUtil.getAgentAddress(agentId);
      } catch (e) {
        agentAddress = 'unknown';
      }
    }

    return Wallet(
      id: id,
      name: name,
      seedHex: seedHex,
      agentId: agentId,
      agentAddress: agentAddress,
    );
  }
}
