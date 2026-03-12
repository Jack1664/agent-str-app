class ChatMessage {
  final String content;
  final String signature;
  final String senderPubKeyHex;
  final int timestamp;
  final bool isMine;

  ChatMessage({
    required this.content,
    required this.signature,
    required this.senderPubKeyHex,
    required this.timestamp,
    this.isMine = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'signature': signature,
      'senderPubKeyHex': senderPubKeyHex,
      'timestamp': timestamp,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      content: json['content'] as String,
      signature: json['signature'] as String,
      senderPubKeyHex: json['senderPubKeyHex'] as String,
      timestamp: json['timestamp'] as int,
    );
  }
}
