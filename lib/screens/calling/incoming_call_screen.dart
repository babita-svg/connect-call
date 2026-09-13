import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/call_model.dart';
import '../../models/user_model.dart';
import '../../providers/call_provider.dart';
import '../../services/call_service.dart';
import '../../services/user_service.dart';
import 'audio_call_screen.dart';
import 'video_call_screen.dart';

/// Modal incoming-call dialog.
///
/// Shows the caller's photo, a call-type badge, and Answer/Decline actions
/// with fade/scale/pulse animations. The dialog cannot be dismissed by tapping
/// outside or pressing back; it auto-rejects after 60s and auto-dismisses if
/// the call ends while it is on screen.
class IncomingCallScreen extends StatefulWidget {
  final CallModel call;

  const IncomingCallScreen({super.key, required this.call});

  /// Presents the incoming-call dialog over the current navigator.
  static Future<void> show(BuildContext context, CallModel call) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => IncomingCallScreen(call: call),
    );
  }

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with TickerProviderStateMixin {
  // Fade-in of the whole dialog.
  late final AnimationController _fadeController;
  late final Animation<double> _fade;

  // Repeating pulse on the Answer button.
  late final AnimationController _pulseController;
  late final Animation<double> _pulse;

  // 60s timeout → auto-reject (missed).
  Timer? _timeoutTimer;

  // Pop guard so we never navigate/dismiss twice (button taps, timeout,
  // and the auto-dismiss-on-end path all race).
  bool _dismissing = false;

  // Caller profile (for the photo); fetched from Firestore in initState.
  UserModel? _caller;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fade = CurvedAnimation(parent: _fadeController, curve: Curves.easeIn);
    _fadeController.forward();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    );
    _pulse = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);

    // Ringtone (optional bonus): start playback here, e.g.
    //   _ringPlayer = AudioPlayer()..setReleaseMode(ReleaseMode.loop)..play(AssetSource('sounds/ringtone.mp3'));
    // Stop it in _stopRingtone().

    _timeoutTimer = Timer(const Duration(seconds: 60), _autoReject);
    _fetchCaller();
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _stopRingtone();
    _fadeController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Stops any playing ringtone (no-op until a sound is wired up).
  void _stopRingtone() {
    // Uncomment when a ringtone is configured:
    // _ringPlayer?.stop();
  }

  // --------------------------------------------------------------------------
  // Data
  // --------------------------------------------------------------------------

  Future<void> _fetchCaller() async {
    try {
      final user = await UserService().getUser(widget.call.callerId);
      if (!mounted) return;
      if (user.photoUrl != null && user.photoUrl!.isNotEmpty) {
        setState(() => _caller = user);
      }
    } catch (_) {
      // Caller profile missing → the default avatar is shown instead.
    }
  }

  // --------------------------------------------------------------------------
  // Actions
  // --------------------------------------------------------------------------

  void _accept() {
    if (_dismissing) return;
    _dismissing = true;
    _stopRingtone();

    final call = widget.call;
    final navigator = Navigator.of(context);
    final cp = context.read<CallProvider>();

    cp.acceptCall(call.id, call.callType == CallType.video);

    // Replace the dialog with the live call screen: pop the dialog, then push.
    // Navigator queues these, so the call screen lands on top of the app shell.
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (_) =>
            call.callType == CallType.video
                ? const VideoCallScreen()
                : const AudioCallScreen(),
      ),
    );
  }

  void _decline() {
    if (_dismissing) return;
    _dismissing = true;
    _stopRingtone();
    context.read<CallProvider>().rejectCall(widget.call.id);
    Navigator.of(context).pop();
  }

  void _autoReject() {
    if (_dismissing) return;
    _dismissing = true;
    _stopRingtone();
    context.read<CallProvider>().rejectCall(widget.call.id);
    if (mounted) Navigator.of(context).pop();
  }

  bool _isTerminal(CallState state) {
    return state == CallState.ended ||
        state == CallState.rejected ||
        state == CallState.missed ||
        state == CallState.busy;
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final call = widget.call;
    final isVideo = call.callType == CallType.video;

    return Consumer<CallProvider>(
      builder: (context, cp, _) {
        // If the call already ended elsewhere, dismiss this dialog.
        final state = cp.callState;
        if (_isTerminal(state) && !_dismissing) {
          _dismissing = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }

        return PopScope(
          // Never dismiss via the system back button — the user must Answer
          // or Decline explicitly.
          canPop: false,
          child: FadeTransition(
            opacity: _fade,
            child: Dialog(
              backgroundColor: const Color(0xFF16172B),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 32,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(28),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ---- Caller photo (150x150 circular) + type badge ----
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        _CallerPhoto(
                          photoUrl: _caller?.photoUrl,
                          name: call.callerName,
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: _CallTypeBadge(isVideo: isVideo),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ---- Caller name (24sp) ----
                    Text(
                      call.callerName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // ---- Call type label ----
                    Text(
                      isVideo ? 'Incoming video call' : 'Incoming audio call',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white.withAlpha(190),
                      ),
                    ),
                    const SizedBox(height: 36),

                    // ---- Actions ----
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ActionButton(
                          icon: Icons.call_end,
                          label: 'Decline',
                          color: Colors.red.shade600,
                          onPressed: _decline,
                        ),
                        // Answer pulses to draw the eye to the positive action.
                        ScaleTransition(
                          scale: _pulse,
                          child: _ActionButton(
                            icon: isVideo ? Icons.videocam : Icons.call,
                            label: 'Answer',
                            color: Colors.green.shade600,
                            onPressed: _accept,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// Building blocks
// ============================================================================

/// 150x150 circular caller avatar with an initial fallback.
class _CallerPhoto extends StatelessWidget {
  final String? photoUrl;
  final String name;

  const _CallerPhoto({required this.photoUrl, required this.name});

  String get _initial => name.isEmpty ? '?' : name.trim()[0].toUpperCase();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFF23243F),
        boxShadow: [
          BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      padding: const EdgeInsets.all(4),
      child: CircleAvatar(
        radius: 72,
        backgroundColor: const Color(0xFF2E3052),
        foregroundImage: (photoUrl != null && photoUrl!.isNotEmpty)
            ? CachedNetworkImageProvider(photoUrl!)
            : null,
        child: (photoUrl == null || photoUrl!.isEmpty)
            ? Text(
                _initial,
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              )
            : null,
      ),
    );
  }
}

/// Small pill (top-right of the photo) saying Audio or Video.
class _CallTypeBadge extends StatelessWidget {
  final bool isVideo;
  const _CallTypeBadge({required this.isVideo});

  @override
  Widget build(BuildContext context) {
    final color = isVideo ? Colors.green.shade600 : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(isVideo ? Icons.videocam : Icons.call, size: 16, color: Colors.white),
          const SizedBox(width: 4),
          Text(
            isVideo ? 'Video' : 'Audio',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Circular action button with a clear label underneath and a press-scale
/// animation. Sized ≥64px so the touch target is comfortably above 48dp.
class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.88 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: widget.color.withAlpha(120),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(widget.icon, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 10),
              Text(
                widget.label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}