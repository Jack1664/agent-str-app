class Friend {
  final String pubKeyHex;
  String alias;
  bool isBlacklisted;

  Friend({
    required this.pubKeyHex,
    required this.alias,
    this.isBlacklisted = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'pubKeyHex': pubKeyHex,
      'alias': alias,
      'isBlacklisted': isBlacklisted,
    };
  }

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      pubKeyHex: json['pubKeyHex'] as String,
      alias: json['alias'] as String,
      isBlacklisted: json['isBlacklisted'] as bool? ?? false,
    );
  }
}
