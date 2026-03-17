import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../models/chat_message.dart';

class VoiceMessageBubble extends StatefulWidget {
  const VoiceMessageBubble({
    super.key,
    required this.message,
    required this.isMine,
  });

  final ChatMessage message;
  final bool isMine;

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final AudioPlayer _player = AudioPlayer();

  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  bool _isResettingAfterComplete = false;

  bool _isReady = false;
  bool _isPlaying = false;
  bool _hasError = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _bindPlayer();
    unawaited(_prepare());
  }

  void _bindPlayer() {
    _playerStateSubscription = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed &&
          !_isResettingAfterComplete) {
        _isResettingAfterComplete = true;
        unawaited(_resetAfterCompletion());
      }

      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed ||
            _isResettingAfterComplete) {
          _position = Duration.zero;
        }
      });
    });

    _positionSubscription = _player.positionStream.listen((position) {
      if (!mounted) return;
      setState(() {
        _position = position;
      });
    });

    _durationSubscription = _player.durationStream.listen((duration) {
      if (!mounted || duration == null) return;
      setState(() {
        _duration = duration;
      });
    });
  }

  Future<void> _resetAfterCompletion() async {
    await _player.stop();
    await _player.seek(Duration.zero);
    if (!mounted) return;
    setState(() {
      _isPlaying = false;
      _position = Duration.zero;
    });
    _isResettingAfterComplete = false;
  }

  Future<void> _prepare() async {
    final localPath = widget.message.localAudioPath;
    final audioUri = widget.message.audioUri;
    if ((localPath == null || localPath.isEmpty) &&
        (audioUri == null || audioUri.isEmpty)) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
      return;
    }

    try {
      Duration? duration;
      if (localPath != null && localPath.isNotEmpty) {
        final file = File(localPath);
        if (file.existsSync()) {
          duration = await _player.setFilePath(localPath);
        }
      }

      if (duration == null && audioUri != null && audioUri.isNotEmpty) {
        final parsedUri = Uri.tryParse(audioUri);
        if (parsedUri != null &&
            parsedUri.hasScheme &&
            (parsedUri.scheme == 'http' || parsedUri.scheme == 'https')) {
          duration = await _player.setUrl(audioUri);
        } else {
          final fallbackFile = File(audioUri);
          if (fallbackFile.existsSync()) {
            duration = await _player.setFilePath(audioUri);
          }
        }
      }

      if (duration == null) {
        throw StateError('Audio source unavailable');
      }

      if (!mounted) return;
      setState(() {
        _isReady = true;
        _duration =
            duration ??
            Duration(milliseconds: widget.message.voiceDurationMs ?? 0);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
      });
    }
  }

  @override
  void dispose() {
    _playerStateSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (!_isReady || _hasError) return;

    if (_isPlaying) {
      await _player.pause();
      return;
    }

    final effectiveDuration = _effectiveDuration;
    if (_position >= effectiveDuration && effectiveDuration > Duration.zero) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  Duration get _effectiveDuration {
    if (_duration > Duration.zero) return _duration;
    final durationMs = widget.message.voiceDurationMs;
    if (durationMs == null || durationMs <= 0) return Duration.zero;
    return Duration(milliseconds: durationMs);
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds;
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final effectiveDuration = _effectiveDuration;
    final clampedPosition = effectiveDuration > Duration.zero
        ? Duration(
            milliseconds: math.min(
              _position.inMilliseconds,
              effectiveDuration.inMilliseconds,
            ),
          )
        : Duration.zero;

    final progress = effectiveDuration.inMilliseconds == 0
        ? 0.0
        : clampedPosition.inMilliseconds / effectiveDuration.inMilliseconds;

    final backgroundColor = widget.isMine
        ? const Color(0xFF00D1C1)
        : Colors.white;
    final borderColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.14)
        : const Color(0xFFE6EDF5);
    final foregroundColor = widget.isMine
        ? Colors.white
        : const Color(0xFF122033);
    final secondaryColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF708198);
    final trackColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.22)
        : const Color(0xFFE7EDF3);
    final activeTrackColor = widget.isMine
        ? Colors.white
        : const Color(0xFF00B7A8);
    final playButtonColor = widget.isMine
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFF4F7FA);
    final playIconColor = widget.isMine
        ? Colors.white
        : const Color(0xFF0F172A);

    return GestureDetector(
      onTap: _togglePlayback,
      child: SizedBox(
        width: 232,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: widget.isMine ? 0.08 : 0.05,
                ),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: playButtonColor,
                ),
                child: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: playIconColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 18,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: List.generate(20, (index) {
                          final seed = ((index * 37) % 9) + 6;
                          final barHeight = seed.toDouble();
                          final active = progress > (index / 20);
                          return Expanded(
                            child: Align(
                              alignment: Alignment.center,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeOut,
                                width: 3,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: active ? activeTrackColor : trackColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          _formatDuration(clampedPosition),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: foregroundColor,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(effectiveDuration),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: secondaryColor,
                          ),
                        ),
                      ],
                    ),
                    if (_hasError) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Audio unavailable',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: widget.isMine
                              ? Colors.white.withValues(alpha: 0.82)
                              : const Color(0xFFD93025),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
