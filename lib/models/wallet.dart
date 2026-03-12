import '../core/crypto_util.dart';

class Wallet {
  final String id;
  String name;
  final String encryptedBase64Seed;
  final String agentId; // Public Key Hex
  final String agentAddress; // Bech32 Address

  Wallet({
    required this.id,
    required this.name,
    required this.encryptedBase64Seed,
    required this.agentId,
    required this.agentAddress,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'encryptedBase64Seed': encryptedBase64Seed,
      'agentId': agentId,
      'agentAddress': agentAddress,
    };
  }

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final String id = json['id'] as String? ?? '';
    final String name = json['name'] as String? ?? 'Unnamed Wallet';
    final String encryptedBase64Seed = json['encryptedBase64Seed'] as String? ?? '';

    // 兼容旧字段 publicKeyHex
    final String agentId = json['agentId'] as String? ?? json['publicKeyHex'] as String? ?? '';

    // 自动迁移：如果 agentAddress 为空但有 agentId，则重新生成它
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
      encryptedBase64Seed: encryptedBase64Seed,
      agentId: agentId,
      agentAddress: agentAddress,
    );
  }
}
