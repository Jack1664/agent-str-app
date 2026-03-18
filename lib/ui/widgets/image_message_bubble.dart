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

    final heroTag =
        'image_${message.signature}_${message.timestamp}_${message.senderPubKeyHex}';

    Widget child;
    if (localPath != null &&
        localPath.isNotEmpty &&
        File(localPath).existsSync()) {
      child = Hero(
        tag: heroTag,
        child: Image.file(
          File(localPath),
          fit: BoxFit.cover,
          width: 220,
          height: 220,
        ),
      );
    } else if (imageUri != null &&
        imageUri.isNotEmpty &&
        (imageUri.startsWith('http://') || imageUri.startsWith('https://'))) {
      child = Hero(
        tag: heroTag,
        child: Image.network(
          imageUri,
          fit: BoxFit.cover,
          width: 220,
          height: 220,
        ),
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

    final canPreview =
        (localPath != null &&
            localPath.isNotEmpty &&
            File(localPath).existsSync()) ||
        (imageUri != null &&
            imageUri.isNotEmpty &&
            (imageUri.startsWith('http://') ||
                imageUri.startsWith('https://')));

    return GestureDetector(
      onTap: canPreview
          ? () => _showFullscreenPreview(
              context,
              heroTag: heroTag,
              localPath: localPath,
              imageUri: imageUri,
            )
          : null,
      child: ClipRRect(borderRadius: borderRadius, child: child),
    );
  }

  void _showFullscreenPreview(
    BuildContext context, {
    required String heroTag,
    required String? localPath,
    required String? imageUri,
  }) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) {
        Widget preview;
        if (localPath != null &&
            localPath.isNotEmpty &&
            File(localPath).existsSync()) {
          preview = Hero(tag: heroTag, child: Image.file(File(localPath)));
        } else if (imageUri != null &&
            imageUri.isNotEmpty &&
            (imageUri.startsWith('http://') ||
                imageUri.startsWith('https://'))) {
          preview = Hero(tag: heroTag, child: Image.network(imageUri));
        } else {
          preview = const Icon(
            Icons.broken_image_outlined,
            color: Colors.white,
            size: 56,
          );
        }

        return Dialog.fullscreen(
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(color: Colors.transparent),
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(child: preview),
                  ),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: SafeArea(
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withValues(alpha: 0.28),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
