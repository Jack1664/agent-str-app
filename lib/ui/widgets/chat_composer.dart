import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'top_notice.dart';

typedef VoiceMessageCallback =
    Future<void> Function(String filePath, Duration duration);

class ChatComposer extends StatefulWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSend,
    this.onAttach,
    this.onMic,
    this.onSendVoice,
    this.pendingImagePath,
    this.onRemoveAttachment,
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback onSend;
  final VoidCallback? onAttach;
  final VoidCallback? onMic;
  final VoiceMessageCallback? onSendVoice;
  final String? pendingImagePath;
  final VoidCallback? onRemoveAttachment;

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer>
    with TickerProviderStateMixin {
  final AudioRecorder _recorder = AudioRecorder();

  late final AnimationController _pulseController;
  Timer? _recordingTimer;

  bool _isRecording = false;
  bool _cancelRecording = false;
  Duration _recordingDuration = Duration.zero;
  Offset? _recordingStartGlobalPosition;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    if (_isRecording || widget.onSendVoice == null) return;

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      TopNotice.show(
        'Microphone permission is required for voice messages',
        backgroundColor: Colors.redAccent,
      );
      return;
    }

    final directory = await getTemporaryDirectory();
    final filePath = p.join(
      directory.path,
      'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );

    _recordingTimer?.cancel();
    _recordingDuration = Duration.zero;
    _cancelRecording = false;
    _pulseController.repeat();
    _recordingTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted) {
        setState(() {
          _recordingDuration += const Duration(milliseconds: 100);
        });
      }
    });

    if (mounted) {
      setState(() {
        _isRecording = true;
      });
    }
  }

  Future<void> _finishRecording() async {
    if (!_isRecording) return;

    final didCancel = _cancelRecording;
    final duration = _recordingDuration;

    _recordingTimer?.cancel();
    _pulseController.stop();
    _pulseController.reset();

    String? path;
    if (didCancel) {
      await _recorder.cancel();
    } else {
      path = await _recorder.stop();
    }

    if (mounted) {
      setState(() {
        _isRecording = false;
        _cancelRecording = false;
        _recordingDuration = Duration.zero;
        _recordingStartGlobalPosition = null;
      });
    }

    if (!didCancel &&
        path != null &&
        duration > const Duration(milliseconds: 300) &&
        widget.onSendVoice != null) {
      await widget.onSendVoice!(path, duration);
    }
  }

  void _updateCancelState(LongPressMoveUpdateDetails details) {
    if (!_isRecording) return;
    final shouldCancel = details.offsetFromOrigin.dx < -96;
    if (shouldCancel != _cancelRecording && mounted) {
      setState(() => _cancelRecording = shouldCancel);
    }
  }

  void _updateCancelStateFromPointer(Offset globalPosition) {
    if (!_isRecording || _recordingStartGlobalPosition == null) return;
    final shouldCancel =
        globalPosition.dx - _recordingStartGlobalPosition!.dx < -96;
    if (shouldCancel != _cancelRecording && mounted) {
      setState(() => _cancelRecording = shouldCancel);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString();
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    final centiseconds = ((duration.inMilliseconds % 1000) / 10)
        .floor()
        .toString()
        .padLeft(2, '0');
    return '$minutes:$seconds,$centiseconds';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      color: Colors.transparent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (event) {
          if (_isRecording) {
            _updateCancelStateFromPointer(event.position);
          }
        },
        onPointerUp: (_) {
          if (_isRecording) {
            _finishRecording();
          }
        },
        onPointerCancel: (_) {
          if (_isRecording) {
            _finishRecording();
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!_isRecording && _hasPendingImage) ...[
              _buildImagePreview(),
              const SizedBox(height: 10),
            ],
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeInOut,
              switchOutCurve: Curves.easeInOut,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SizeTransition(
                    sizeFactor: animation,
                    axisAlignment: -1,
                    child: child,
                  ),
                );
              },
              child: _isRecording
                  ? _buildRecordingComposer()
                  : _buildIdleComposer(),
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasPendingImage =>
      widget.pendingImagePath != null && widget.pendingImagePath!.isNotEmpty;

  Widget _buildImagePreview() {
    final imagePath = widget.pendingImagePath!;
    final imageFile = File(imagePath);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: imageFile.existsSync()
                  ? Image.file(
                      imageFile,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      color: const Color(0xFFF4F7FA),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Image selected',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Tap send to deliver',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: widget.onRemoveAttachment,
              icon: const Icon(Icons.close_rounded, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F9),
                foregroundColor: const Color(0xFF475569),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIdleComposer() {
    return Row(
      key: const ValueKey<String>('composer_idle'),
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            children: [
              _AccessoryButton(
                icon: Icons.attach_file_rounded,
                onTap: widget.onAttach ?? () {},
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(minHeight: 48),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F7FA),
                    borderRadius: BorderRadius.circular(26),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.newline,
                    cursorColor: const Color(0xFF00D1C1),
                    style: const TextStyle(
                      fontSize: 16,
                      height: 1.25,
                      color: Color(0xFF1F2937),
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: widget.hintText,
                      hintStyle: const TextStyle(
                        color: Color(0xFF9AA4B2),
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF4F7FA),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _buildPrimaryAction(),
      ],
    );
  }

  Widget _buildRecordingComposer() {
    return SizedBox(
      key: const ValueKey<String>('composer_recording'),
      height: 88,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.centerRight,
        children: [
          Positioned(
            left: 0,
            right: 56,
            top: 22,
            child: _buildRecordingPanel(),
          ),
          Positioned(right: 0, child: _buildPrimaryAction()),
        ],
      ),
    );
  }

  Widget _buildRecordingPanel() {
    return Container(
      height: 42,
      padding: const EdgeInsets.fromLTRB(12, 0, 52, 0),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FBEF),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          topRight: Radius.circular(4),
          bottomRight: Radius.circular(4),
        ),
        border: Border.all(
          color: _cancelRecording
              ? const Color(0xFFFFD1D1)
              : const Color(0xFFE2EFD2),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: _cancelRecording
                  ? const Color(0xFFFF6B6B)
                  : const Color(0xFFFF8AA1),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDuration(_recordingDuration),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.chevron_left_rounded,
            size: 18,
            color: _cancelRecording
                ? const Color(0xFFD93025)
                : const Color(0xFF25352A),
          ),
          Expanded(
            child: Text(
              _cancelRecording ? 'Release to cancel' : 'Slide to cancel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: _cancelRecording
                    ? const Color(0xFFD93025)
                    : const Color(0xFF111827),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: widget.controller,
      builder: (context, value, child) {
        final hasText = value.text.trim().isNotEmpty;
        if ((hasText || _hasPendingImage) && !_isRecording) {
          return _AccessoryButton(
            key: const ValueKey<String>('send_button'),
            icon: Icons.send_rounded,
            onTap: widget.onSend,
            isPrimary: true,
          );
        }

        return GestureDetector(
          key: const ValueKey<String>('mic_button'),
          onTap: !_isRecording ? widget.onMic : null,
          onLongPressStart: (details) async {
            _recordingStartGlobalPosition = details.globalPosition;
            await _startRecording();
          },
          onLongPressMoveUpdate: _updateCancelState,
          child: SizedBox(
            width: _isRecording ? 72 : 44,
            height: _isRecording ? 72 : 44,
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final t = _pulseController.value;
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    if (_isRecording)
                      for (final index in [0, 1])
                        Container(
                          width: 72 + ((t + (index * 0.5)) % 1) * 22,
                          height: 72 + ((t + (index * 0.5)) % 1) * 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color:
                                (_cancelRecording
                                        ? const Color(0xFFFF453A)
                                        : const Color(0xFF0A84FF))
                                    .withValues(
                                      alpha:
                                          0.18 *
                                          (1 - ((t + (index * 0.5)) % 1)),
                                    ),
                          ),
                        ),
                    if (_isRecording)
                      CustomPaint(
                        size: const Size(72, 72),
                        painter: _MicRipplePainter(
                          progress: t,
                          color: _cancelRecording
                              ? const Color(0xFFFFC3BF)
                              : Colors.white,
                        ),
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      width: _isRecording ? 72 : 44,
                      height: _isRecording ? 72 : 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _cancelRecording
                            ? const Color(0xFFFF3B30)
                            : (_isRecording
                                  ? const Color(0xFF0A84FF)
                                  : const Color(0xFF00D1C1)),
                      ),
                      child: Icon(
                        Icons.mic_none_rounded,
                        size: _isRecording ? 30 : 22,
                        color: Colors.white,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _MicRipplePainter extends CustomPainter {
  const _MicRipplePainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final phases = [progress, (progress + 0.45) % 1];

    for (final phase in phases) {
      final radius = 18 + (phase * 12);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2 - (phase * 0.9)
        ..color = color.withValues(alpha: 0.7 - (phase * 0.55));
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MicRipplePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _AccessoryButton extends StatelessWidget {
  const _AccessoryButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isPrimary;

  @override
  Widget build(BuildContext context) {
    final backgroundColor = isPrimary
        ? const Color(0xFF00D1C1)
        : const Color(0xFFF1F4F8);
    final iconColor = isPrimary ? Colors.white : const Color(0xFF607086);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        width: 44,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          boxShadow: isPrimary
              ? [
                  BoxShadow(
                    color: const Color(0xFF00D1C1).withValues(alpha: 0.24),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Icon(icon, color: iconColor, size: 22),
      ),
    );
  }
}
