/// Central place for app-wide constants.
class AppConstants {
  AppConstants._();

  /// Application title used across the UI.
  static const String appName = 'ConnectCall';

  /// Agora App ID — replace with your own from the Agora console.
  static const String agoraAppId = 'YOUR_AGORA_APP_ID';

  /// Collection names in Cloud Firestore.
  static const String usersCollection = 'users';
  static const String callsCollection = 'calls';

  /// Audio/Video codec related settings for Agora.
  static const int defaultVideoWidth = 1280;
  static const int defaultVideoHeight = 720;
  static const int defaultVideoFps = 30;
}