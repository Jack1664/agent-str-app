import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/chat_message.dart';
import 'image_message_bubble.dart';
import 'voice_message_bubble.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.remoteAvatarText,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
  });

  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final String remoteAvatarText;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: padding,
      reverse: true,
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[messages.length - 1 - index];
        return _ChatMessageItem(
          message: message,
          remoteAvatarText: remoteAvatarText,
        );
      },
    );
  }
}

class _ChatMessageItem extends StatelessWidget {
  const _ChatMessageItem({
    required this.message,
    required this.remoteAvatarText,
  });

  final ChatMessage message;
  final String remoteAvatarText;

  @override
  Widget build(BuildContext context) {
    if (message.isSystem) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFE5E5),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFFB8B8)),
            ),
            child: Text(
              message.content,
              style: const TextStyle(
                color: Color(0xFFD93025),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    final isMine = message.isMine;
    final timeStr = DateFormat(
      'HH:mm',
    ).format(DateTime.fromMillisecondsSinceEpoch(message.timestamp));
    final maxWidth = MediaQuery.of(context).size.width * 0.75;
    final agentIdShort = 'Agent ${message.senderPubKeyHex.substring(0, 8)}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.orange.shade100,
              child: Text(
                remoteAvatarText,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.orange,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Column(
              crossAxisAlignment: isMine
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (!isMine)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      agentIdShort,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Container(
                  padding: (message.isVoiceMessage || message.isImageMessage)
                      ? EdgeInsets.zero
                      : const EdgeInsets.only(
                          left: 12,
                          right: 12,
                          top: 8,
                          bottom: 6,
                        ),
                  decoration: BoxDecoration(
                    color: (message.isVoiceMessage || message.isImageMessage)
                        ? Colors.transparent
                        : (isMine ? const Color(0xFF00D1C1) : Colors.white),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: Radius.circular(isMine ? 16 : 4),
                      bottomRight: Radius.circular(isMine ? 4 : 16),
                    ),
                    boxShadow:
                        (message.isVoiceMessage || message.isImageMessage)
                        ? null
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                  ),
                  child: message.isVoiceMessage
                      ? VoiceMessageBubble(message: message, isMine: isMine)
                      : message.isImageMessage
                      ? ImageMessageBubble(message: message, isMine: isMine)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              message.content,
                              style: TextStyle(
                                color: isMine
                                    ? Colors.white
                                    : const Color(0xFF1A1A1A),
                                fontSize: 15,
                                height: 1.4,
                              ),
                              textAlign: TextAlign.left,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              timeStr,
                              style: TextStyle(
                                color: isMine
                                    ? Colors.white.withValues(alpha: 0.74)
                                    : const Color(0xFF94A3B8),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                ),
                if (message.isVoiceMessage || message.isImageMessage) ...[
                  const SizedBox(height: 4),
                  Text(
                    timeStr,
                    style: const TextStyle(
                      color: Color(0xFF94A3B8),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (isMine) const SizedBox(width: 4),
        ],
      ),
    );
  }
}
