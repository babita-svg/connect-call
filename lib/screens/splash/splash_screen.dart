import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';

/// Animated splash shown while the app restores the persisted auth session.
///
/// Enforces a minimum ~2s branding window: [initState] waits for
/// [AuthProvider.checkAuthStatus] *and* a 2s delay, then invokes [onFinished].
/// The owning auth gate (see `main.dart` → `_AppRoot`) reacts to the restored
/// session by showing the home or login screen, so logout keeps routing back
/// to login automatically. Errors during the check fall through gracefully —
/// the gate will just show the login screen.
class SplashScreen extends StatefulWidget {
  /// Called once the auth check and the minimum branding delay have completed.
  final VoidCallback onFinished;

  const SplashScreen({super.key, required this.onFinished});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Logo scale: 0.5 → 1.0 over the full 1s animation.
  late final Animation<double> _scale;

  /// Tagline opacity: fades in over the second half, i.e. after ~0.5s.
  late final Animation<double> _taglineOpacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _scale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );
    _taglineOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
    );
    _controller.forward();
    _bootstrap();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Checks the persisted session while the branding shows, in parallel with a
  /// 2s minimum display time. Never throws on its own; a failed check just
  /// leaves the auth gate on the login screen.
  Future<void> _bootstrap() async {
    try {
      await Future.wait([
        context.read<AuthProvider>().checkAuthStatus(),
        Future<void>.delayed(const Duration(seconds: 2)),
      ]);
    } catch (e) {
      debugPrint('SplashScreen bootstrap failed: $e');
    }
    if (mounted) widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.primaryColor, Color(0xFF1E3A8A)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Animated brand logo (scales in from 0.5).
                  ScaleTransition(
                    scale: _scale,
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.videocam,
                        size: 52,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'ConnectCall',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  // Tagline (fades in after ~0.5s).
                  FadeTransition(
                    opacity: _taglineOpacity,
                    child: const Text(
                      'Connect with anyone, anywhere',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  const SizedBox(height: 56),
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}