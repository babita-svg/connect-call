import 'dart:async';

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../providers/call_provider.dart';
import '../../services/call_service.dart';

// ============================================================================
// Theme constants
// ============================================================================

const Color _activeColor = Color(0xFF2563EB);
const Color _inactiveColor = Color(0xFF9E9E9E);
const Color _endColor = Colors.red;
const Color _connectedBadge = Colors.green;
const Color _connectingBadge = Colors.amber;
const Color _barBg = Color(0xB3000000);
const Duration _hideDelay = Duration(seconds: 5);
const Duration _dismissDelay = Duration(seconds: 2);

// ============================================================================
// Public widget
// ============================================================================

/// Full-screen video call UI with local video, remote overlay, info bar,
/// auto-hiding controls, and lifecycle/permission handling.
class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

// ============================================================================
// State
// ============================================================================

class _VideoCallScreenState extends State<VideoCallScreen>
    with WidgetsBindingObserver {
  // Permissions
  bool _micGranted = false;
  bool _cameraGranted = false;

  // Controls auto-hide
  bool _controlsVisible = true;
  Timer? _hideTimer;

  // Auto-dismiss when call ends
  Timer? _dismissTimer;

  // Permission-denied banner
  bool _showPermBanner = false;

  // Network banner
  bool _showNetworkBanner = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lockOrientation();
    _hideStatusBar();
    _requestPermissions();
    _startHideTimer();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _dismissTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _restoreOrientation();
    _restoreStatusBar();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Show a banner reminder when the user returns from background so they
    // know the call is still active.
    if (state == AppLifecycleState.resumed) {
      setState(() => _showNetworkBanner = false);
    }
  }

  // --------------------------------------------------------------------------
  // Permissions
  // --------------------------------------------------------------------------

  Future<void> _requestPermissions() async {
    final mic = await Permission.microphone.request();
    final cam = await Permission.camera.request();
    if (!mounted) return;
    setState(() {
      _micGranted = mic.isGranted;
      _cameraGranted = cam.isGranted;
      _showPermBanner = !(mic.isGranted && cam.isGranted);
    });
  }

  void _openSettings() => openAppSettings();

  // --------------------------------------------------------------------------
  // Orientation / status bar
  // --------------------------------------------------------------------------

  void _lockOrientation() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
  }

  void _hideStatusBar() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _restoreOrientation() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _restoreStatusBar() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  // --------------------------------------------------------------------------
  // Controls auto-hide
  // --------------------------------------------------------------------------

  void _onScreenTap() {
    setState(() => _controlsVisible = true);
    _startHideTimer();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  // --------------------------------------------------------------------------
  // Call ended handling
  // --------------------------------------------------------------------------

  void _maybeDismiss(CallState state) {
    final terminal = state == CallState.ended ||
        state == CallState.rejected ||
        state == CallState.missed ||
        state == CallState.busy;

    if (!terminal) return;
    if (_dismissTimer?.isActive == true) return;

    _dismissTimer = Timer(_dismissDelay, () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.read<CallProvider>().endCall();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Consumer<CallProvider>(
          builder: (context, cp, _) {
            final state = cp.callState;
            _maybeDismiss(state);

            final call = cp.currentCall;
            final name = call?.calleeName ?? 'Unknown';
            final connected = state == CallState.connected;
            final connecting =
                state == CallState.calling || state == CallState.ringing;

            _showNetworkBanner = state == CallState.failed;

            return GestureDetector(
              behavior: HitTestBehavior.deferToChild,
              onTap: _onScreenTap,
              child: Stack(
                children: [
                  // 1 ── Local video (full screen)
                  Positioned.fill(
                    child: _cameraGranted
                        ? AgoraVideoView(
                            controller: VideoViewController(
                              rtcEngine: cp.callService.engine,
                              canvas: VideoCanvas(uid: 0),
                              rtcConnection: const RtcConnection(
                                channelId: '',
                              ),
                            ),
                            placeholderBuilder: (_, __) =>
                                const _VideoPlaceholder(),
                          )
                        : const _VideoPlaceholder(),
                  ),

                  // 2 ── Remote video overlay (top-right)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 16,
                    right: 16,
                    width: 120,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: _RemoteOverlay(
                        callService: cp.callService,
                        hasPermission: _cameraGranted,
                      ),
                    ),
                  ),

                  // 3 ── Call info bar (top, semi-transparent)
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    right: 16,
                    child: _CallInfoBar(
                      name: name,
                      duration: cp.durationString,
                      connected: connected,
                      connecting: connecting,
                      visible: _controlsVisible,
                    ),
                  ),

                  // 4 ── Control buttons bar (bottom, semi-transparent)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: MediaQuery.of(context).padding.bottom + 24,
                    child: AnimatedOpacity(
                      opacity: _controlsVisible ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: !_controlsVisible,
                        child: _ControlsBar(
                          isMuted: cp.isAudioMuted,
                          isCameraOn: cp.isVideoEnabled,
                          onMute: () => cp.toggleAudio(),
                          onCamera: () => cp.toggleVideo(),
                          onSwitch: () => cp.switchCamera(),
                          onEnd: () => cp.endCall(),
                        ),
                      ),
                    ),
                  ),

                  // Network quality indicator (shown once connected)
                  if (connected)
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: MediaQuery.of(context).padding.bottom + 140,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: cp.networkQuality == NetworkQuality.good
                                ? Colors.green.shade600
                                : cp.networkQuality == NetworkQuality.fair
                                    ? Colors.amber.shade600
                                    : Colors.red.shade600,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Network: ${cp.networkQuality.name.toUpperCase()}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Permission denied banner
                  if (_showPermBanner)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 4,
                      left: 16,
                      right: 16,
                      child: _Banner(
                        message: 'Camera and microphone permissions are required.',
                        actionLabel: 'Settings',
                        color: Colors.red.shade800,
                        onAction: _openSettings,
                      ),
                    ),

                  // Network disconnected banner
                  if (_showNetworkBanner)
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 4,
                      left: 16,
                      right: 16,
                      child: _Banner(
                        message: 'Network connection lost.',
                        color: _connectingBadge,
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// Sub-widgets
// ============================================================================

/// Fallback when no video is available (permission denied / not yet joined).
class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.videocam_off, color: Colors.white24, size: 64),
      ),
    );
  }
}

/// Small top-right overlay showing the remote participant's video.
class _RemoteOverlay extends StatelessWidget {
  final CallService callService;
  final bool hasPermission;

  const _RemoteOverlay({required this.callService, required this.hasPermission});

  @override
  Widget build(BuildContext context) {
    final remoteUid =
        int.tryParse(callService.remoteUserId ?? '') ?? 0;

    if (!hasPermission || remoteUid == 0) {
      return Container(
        color: Colors.grey.shade900,
        child: const Center(
          child: Icon(Icons.person, color: Colors.white54),
        ),
      );
    }

    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: callService.engine,
        canvas: VideoCanvas(uid: remoteUid),
        connection: const RtcConnection(channelId: ''),
      ),
    );
  }
}

/// Top bar showing caller name, duration, and connection badge.
class _CallInfoBar extends StatelessWidget {
  final String name;
  final String duration;
  final bool connected;
  final bool connecting;
  final bool visible;

  const _CallInfoBar({
    required this.name,
    required this.duration,
    required this.connected,
    required this.connecting,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _barBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    duration,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _StatusBadge(connected: connected, connecting: connecting),
          ],
        ),
      ),
    );
  }
}

/// Pill-shaped badge: green for connected, yellow for connecting.
class _StatusBadge extends StatelessWidget {
  final bool connected;
  final bool connecting;
  const _StatusBadge({required this.connected, required this.connecting});

  @override
  Widget build(BuildContext context) {
    final color =
        connected ? _connectedBadge : (connecting ? _connectingBadge : Colors.grey);
    final label = connected ? 'Connected' : (connecting ? 'Connecting' : '—');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Bottom control bar with four buttons.
class _ControlsBar extends StatelessWidget {
  final bool isMuted;
  final bool isCameraOn;
  final VoidCallback onMute;
  final VoidCallback onCamera;
  final VoidCallback onSwitch;
  final VoidCallback onEnd;

  const _ControlsBar({
    required this.isMuted,
    required this.isCameraOn,
    required this.onMute,
    required this.onCamera,
    required this.onSwitch,
    required this.onEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: _barBg,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ControlCircle(
            icon: isMuted ? Icons.mic_off : Icons.mic,
            active: !isMuted,
            onPressed: onMute,
          ),
          _ControlCircle(
            icon: isCameraOn ? Icons.videocam : Icons.videocam_off,
            active: isCameraOn,
            onPressed: onCamera,
          ),
          _ControlCircle(
            icon: Icons.cameraswitch,
            active: true,
            onPressed: onSwitch,
          ),
          _ControlCircle(
            icon: Icons.call_end,
            isEnd: true,
            onPressed: onEnd,
          ),
        ],
      ),
    );
  }
}

/// Individual control button with press-scale animation.
class _ControlCircle extends StatefulWidget {
  final IconData icon;
  final bool active;
  final bool isEnd;
  final VoidCallback onPressed;

  const _ControlCircle({
    required this.icon,
    this.active = false,
    this.isEnd = false,
    required this.onPressed,
  });

  @override
  State<_ControlCircle> createState() => _ControlCircleState();
}

class _ControlCircleState extends State<_ControlCircle> {
  bool _pressed = false;

  Color get _bg {
    if (widget.isEnd) return _endColor;
    return _pressed ? _activeColor.withAlpha(200) : _inactiveColor.withAlpha(100);
  }

  Color get _iconColor {
    if (widget.isEnd) return Colors.white;
    return widget.active ? Colors.white : Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onPressed();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.85 : 1.0,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOutCubic,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: _bg, shape: BoxShape.circle),
          child: Icon(widget.icon, color: _iconColor, size: 28),
        ),
      ),
    );
  }
}

/// Warning banner with optional action button.
class _Banner extends StatelessWidget {
  final String message;
  final String? actionLabel;
  final Color color;
  final VoidCallback? onAction;

  const _Banner({
    required this.message,
    this.actionLabel,
    required this.color,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              child: Text(
                actionLabel!,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}