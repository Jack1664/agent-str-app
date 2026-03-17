import 'dart:convert';

class ChatMessage {
  final String content;
  final String signature;
  final String senderPubKeyHex;
  final int timestamp;
  final bool isMine;
  final bool isSystem;
  final String contentType;
  final Map<String, dynamic> metadata;
  final List<Map<String, dynamic>> attachments;

  ChatMessage({
    required this.content,
    required this.signature,
    required this.senderPubKeyHex,
    required this.timestamp,
    this.isMine = false,
    this.isSystem = false,
    this.contentType = 'text/plain',
    Map<String, dynamic>? metadata,
    List<Map<String, dynamic>>? attachments,
  }) : metadata = metadata ?? const {},
       attachments = attachments ?? const [];

  bool get isVoiceMessage =>
      contentType.startsWith('audio/') ||
      metadata['message_type'] == 'voice' ||
      attachments.any((attachment) => attachment['type'] == 'audio');

  int? get voiceDurationMs {
    final metadataDuration = metadata['duration_ms'];
    if (metadataDuration is int) return metadataDuration;
    final attachmentDuration = attachments.isNotEmpty
        ? attachments.first['duration_ms']
        : null;
    return attachmentDuration is int ? attachmentDuration : null;
  }

  String? get localAudioPath {
    final metadataPath = metadata['local_path'];
    if (metadataPath is String && metadataPath.isNotEmpty) return metadataPath;
    final attachmentPath = attachments.isNotEmpty
        ? attachments.first['local_path']
        : null;
    return attachmentPath is String && attachmentPath.isNotEmpty
        ? attachmentPath
        : null;
  }

  String? get audioUri {
    final metadataUri = metadata['uri'];
    if (metadataUri is String && metadataUri.isNotEmpty) return metadataUri;
    final attachmentUri = attachments.isNotEmpty
        ? attachments.first['uri']
        : null;
    return attachmentUri is String && attachmentUri.isNotEmpty
        ? attachmentUri
        : null;
  }

  Map<String, dynamic> toJson() {
    return {
      'content': content,
      'signature': signature,
      'senderPubKeyHex': senderPubKeyHex,
      'timestamp': timestamp,
      'isSystem': isSystem,
      'contentType': contentType,
      'metadata': metadata,
      'attachments': attachments,
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawMetadata = json['metadata'];
    final rawAttachments = json['attachments'];
    return ChatMessage(
      content: json['content'] as String,
      signature: json['signature'] as String,
      senderPubKeyHex: json['senderPubKeyHex'] as String,
      timestamp: json['timestamp'] as int,
      isSystem: json['isSystem'] as bool? ?? false,
      isMine: json['isMine'] as bool? ?? false,
      contentType: json['contentType'] as String? ?? 'text/plain',
      metadata: rawMetadata is Map<String, dynamic>
          ? rawMetadata
          : rawMetadata is String && rawMetadata.isNotEmpty
          ? Map<String, dynamic>.from(jsonDecode(rawMetadata) as Map)
          : const {},
      attachments: rawAttachments is List
          ? rawAttachments
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList()
          : rawAttachments is String && rawAttachments.isNotEmpty
          ? (jsonDecode(rawAttachments) as List)
                .map((item) => Map<String, dynamic>.from(item as Map))
                .toList()
          : const [],
    );
  }
}
