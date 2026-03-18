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
      attachments.any(_isAudioAttachment);

  bool get isImageMessage =>
      contentType.startsWith('image/') ||
      metadata['message_type'] == 'image' ||
      attachments.any(_isImageAttachment);

  int? get voiceDurationMs {
    final metadataDuration = metadata['duration_ms'];
    final audioAttachment = attachments
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (attachment) => attachment != null && _isAudioAttachment(attachment),
          orElse: () => null,
        );
    final attachmentDuration = audioAttachment?['duration_ms'];
    if (attachmentDuration is int) return attachmentDuration;
    if (metadataDuration is int) return metadataDuration;
    return attachmentDuration is int ? attachmentDuration : null;
  }

  String? get localAudioPath {
    final audioAttachment = attachments
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (attachment) => attachment != null && _isAudioAttachment(attachment),
          orElse: () => null,
        );
    final attachmentPath = audioAttachment?['local_path'];
    if (attachmentPath is String && attachmentPath.isNotEmpty) {
      return attachmentPath;
    }
    final metadataPath = metadata['local_path'];
    return metadataPath is String && metadataPath.isNotEmpty
        ? metadataPath
        : null;
  }

  String? get audioUri {
    final audioAttachment = attachments
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (attachment) => attachment != null && _isAudioAttachment(attachment),
          orElse: () => null,
        );
    final attachmentUri = audioAttachment?['uri'];
    if (attachmentUri is String && attachmentUri.isNotEmpty) {
      return attachmentUri;
    }
    final metadataUri = metadata['uri'];
    return metadataUri is String && metadataUri.isNotEmpty ? metadataUri : null;
  }

  String? get localImagePath {
    final imageAttachment = attachments
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (attachment) => attachment != null && _isImageAttachment(attachment),
          orElse: () => null,
        );
    final attachmentPath = imageAttachment?['local_path'];
    if (attachmentPath is String && attachmentPath.isNotEmpty) {
      return attachmentPath;
    }
    final metadataPath = metadata['local_path'];
    return metadataPath is String && metadataPath.isNotEmpty
        ? metadataPath
        : null;
  }

  String? get imageUri {
    final imageAttachment = attachments
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (attachment) => attachment != null && _isImageAttachment(attachment),
          orElse: () => null,
        );
    final attachmentUri = imageAttachment?['uri'];
    if (attachmentUri is String && attachmentUri.isNotEmpty) {
      return attachmentUri;
    }
    final metadataUri = metadata['uri'];
    return metadataUri is String && metadataUri.isNotEmpty ? metadataUri : null;
  }

  bool _isAudioAttachment(Map<String, dynamic> attachment) {
    final type = attachment['type'];
    if (type is String && type.toLowerCase() == 'audio') return true;
    final mimeType = attachment['mime_type'];
    if (mimeType is String && mimeType.toLowerCase().startsWith('audio/')) {
      return true;
    }
    final name = attachment['name'];
    if (name is String) {
      final lower = name.toLowerCase();
      if (lower.endsWith('.ogg') ||
          lower.endsWith('.mp3') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.m4a') ||
          lower.endsWith('.aac')) {
        return true;
      }
    }
    return false;
  }

  bool _isImageAttachment(Map<String, dynamic> attachment) {
    final type = attachment['type'];
    if (type is String && type.toLowerCase() == 'image') return true;
    final mimeType = attachment['mime_type'];
    if (mimeType is String && mimeType.toLowerCase().startsWith('image/')) {
      return true;
    }
    final name = attachment['name'];
    if (name is String) {
      final lower = name.toLowerCase();
      if (lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.png') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.webp')) {
        return true;
      }
    }
    return false;
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
