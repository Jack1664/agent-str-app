import 'package:flutter/material.dart';
import 'package:hex/hex.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:typed_data';
import '../core/chat_provider.dart';
import '../core/crypto_util.dart';
import '../core/wallet_provider.dart';
import 'topic_info_screen.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_list.dart';
import 'widgets/top_notice.dart';

class TopicChatScreen extends StatefulWidget {
  final TopicInfo topic;

  const TopicChatScreen({Key? key, required this.topic}) : super(key: key);

  @override
  State<TopicChatScreen> createState() => _TopicChatScreenState();
}

class _TopicChatScreenState extends State<TopicChatScreen> {
  final _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ImagePicker _imagePicker = ImagePicker();
  String? _pendingImagePath;

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final wallet = Provider.of<WalletProvider>(
      context,
      listen: false,
    ).activeWallet!;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final seed = Uint8List.fromList(HEX.decode(wallet.seedHex));
    final keyPair = CryptoUtil.deriveKeyPair(seed);

    chatProvider.sendMessage(
      text,
      keyPair.privateKey,
      wallet.agentId,
      widget.topic.id,
      chatType: "topic",
    );
    _messageController.clear();
  }

  Future<void> _sendMessage() async {
    if (_pendingImagePath != null && _pendingImagePath!.isNotEmpty) {
      final imagePath = _pendingImagePath!;
      final wallet = Provider.of<WalletProvider>(
        context,
        listen: false,
      ).activeWallet!;
      final chatProvider = Provider.of<ChatProvider>(context, listen: false);
      final seed = Uint8List.fromList(HEX.decode(wallet.seedHex));
      final keyPair = CryptoUtil.deriveKeyPair(seed);

      await chatProvider.sendImageMessage(
        imagePath,
        keyPair.privateKey,
        wallet.agentId,
        widget.topic.id,
        chatType: "topic",
      );
      if (!mounted) return;
      setState(() {
        _pendingImagePath = null;
      });
      return;
    }

    await _sendTextMessage();
  }

  Future<void> _sendVoiceMessage(String filePath, Duration duration) async {
    final wallet = Provider.of<WalletProvider>(
      context,
      listen: false,
    ).activeWallet!;
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);

    final seed = Uint8List.fromList(HEX.decode(wallet.seedHex));
    final keyPair = CryptoUtil.deriveKeyPair(seed);

    await chatProvider.sendVoiceMessage(
      filePath,
      duration,
      keyPair.privateKey,
      wallet.agentId,
      widget.topic.id,
      chatType: "topic",
    );
  }

  Future<void> _pickImage() async {
    try {
      final image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 92,
      );
      if (image == null) return;
      if (!mounted) return;
      setState(() {
        _pendingImagePath = image.path;
      });
    } catch (e) {
      if (!mounted) return;
      TopNotice.show(
        'Image access failed. Please allow photo permission.',
        backgroundColor: Colors.redAccent,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = Provider.of<ChatProvider>(context);

    // Find the current topic info from provider to react to alias changes
    final topic = chatProvider.myTopics.firstWhere(
      (t) => t.id == widget.topic.id,
      orElse: () => widget.topic,
    );

    final messages = chatProvider.messages[topic.id] ?? [];
    final char = topic.alias.isNotEmpty ? topic.alias[0].toUpperCase() : '#';

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFFF0F2F5),
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Colors.white,
          elevation: 0.5,
          title: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: const Color(0xFF1A1A1A).withOpacity(0.1),
                child: Text(
                  char,
                  style: const TextStyle(
                    color: Color(0xFF1A1A1A),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      topic.alias,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      topic.id,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade500,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.more_vert, color: Colors.grey),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TopicInfoScreen(topic: topic),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: ChatMessageList(
                messages: messages,
                scrollController: _scrollController,
                remoteAvatarText: 'A',
              ),
            ),
            _buildInputArea(),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea() {
    return ChatComposer(
      controller: _messageController,
      hintText: 'Message...',
      onSend: _sendMessage,
      onAttach: _pickImage,
      onMic: () {},
      onSendVoice: _sendVoiceMessage,
      pendingImagePath: _pendingImagePath,
      onRemoveAttachment: () {
        setState(() {
          _pendingImagePath = null;
        });
      },
    );
  }
}
