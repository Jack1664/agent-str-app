import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/chat_message.dart';

class ImageMessageBubble extends StatelessWidget {
  const ImageMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final localPath = message.localImagePath;
    final imageUri = message.imageUri;
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 6),
      bottomRight: Radius.circular(isMine ? 6 : 18),
    );

    Widget child;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      child = Image.file(
        File(localPath),
        fit: BoxFit.cover,
        width: 220,
        height: 220,
      );
    } else if (imageUri != null &&
        imageUri.isNotEmpty &&
        (imageUri.startsWith('http://') || imageUri.startsWith('https://'))) {
      child = Image.network(
        imageUri,
        fit: BoxFit.cover,
        width: 220,
        height: 220,
      );
    } else {
      child = Container(
        width: 220,
        height: 160,
        color: isMine ? const Color(0xFF00D1C1) : const Color(0xFFF4F7FA),
        alignment: Alignment.center,
        child: Icon(
          Icons.broken_image_outlined,
          color: isMine ? Colors.white : const Color(0xFF64748B),
          size: 36,
        ),
      );
    }

    return ClipRRect(borderRadius: borderRadius, child: child);
  }
}
