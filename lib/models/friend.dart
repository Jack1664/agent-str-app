class Friend {
  final String pubKeyHex;
  String alias;
  bool isBlacklisted;
  bool isPinned;
  int createdAt;

  Friend({
    required this.pubKeyHex,
    required this.alias,
    this.isBlacklisted = false,
    this.isPinned = false,
    int? createdAt,
  }) : this.createdAt = createdAt ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toJson() {
    return {
      'pubKeyHex': pubKeyHex,
      'alias': alias,
      'isBlacklisted': isBlacklisted,
      'isPinned': isPinned,
      'createdAt': createdAt,
    };
  }

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      pubKeyHex: json['pubKeyHex'] as String,
      alias: json['alias'] as String,
      isBlacklisted: json['isBlacklisted'] as bool? ?? false,
      isPinned: json['isPinned'] as bool? ?? false,
      createdAt: json['createdAt'] as int?,
    );
  }
}
