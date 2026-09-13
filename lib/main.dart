import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/call_provider.dart';
import 'providers/user_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await NotificationService().initialize();
  await _grantPermissions();
  runApp(const ConnectCallApp());
}

/// Requests the permissions the app needs for calling.
Future<void> _grantPermissions() async {
  await [
    Permission.microphone,
    Permission.camera,
  ].request();
}

class ConnectCallApp extends StatelessWidget {
  const ConnectCallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => CallProvider()..init()),
      ],
      child: MaterialApp(
        title: 'ConnectCall',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const _AppRoot(),
      ),
    );
  }
}

/// Auth gate. Shows the animated [SplashScreen] while the persisted session is
/// restored, then swaps to the home or login screen. Staying reactive here —
/// instead of having the splash navigate directly — keeps logout routing back
/// to the login screen automatically.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  bool _splashing = true;

  void _onSplashFinished() {
    if (mounted) setState(() => _splashing = false);
  }

  @override
  Widget build(BuildContext context) {
    // Cross-fade between the splash and the first real screen for a smooth
    // transition once the ~2s branding window elapses.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: _splashing
          ? SplashScreen(onFinished: _onSplashFinished)
          : (context.watch<AuthProvider>().isAuthenticated
              ? const HomeScreen()
              : const LoginScreen()),
    );
  }
}