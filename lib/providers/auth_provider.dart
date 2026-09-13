import 'package:flutter/foundation.dart';

import '../core/utils/auth_exceptions.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';

/// Exposes authentication state and actions to the UI.
class AuthProvider extends ChangeNotifier {
  final AuthService _authService;

  AuthProvider({AuthService? authService})
      : _authService = authService ?? AuthService();

  UserModel? _user;
  bool _isLoading = false;
  String? _error;

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _user != null;

  // --------------------------------------------------------------------------
  // Auth actions
  // --------------------------------------------------------------------------

  /// Registers a new account and, on success, stores the returned user.
  Future<void> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.signUp(
        email: email,
        password: password,
        name: name,
      );
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Signs in an existing user and, on success, stores the returned user.
  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _user = await _authService.signIn(email: email, password: password);
    } on AuthException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = 'Something went wrong. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Signs the current user out.
  Future<void> logout() async {
    _isLoading = true;
    notifyListeners();

    try {
      await _authService.logout();
    } finally {
      _user = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Clears the stored error message.
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// Restores the session on app start: re-reads the Firestore profile from
  /// the persisted Firebase session (`_cachedUser` alone is null on a cold
  /// start). Falls back to the cached user if the network read fails, so a
  /// transient error degrades to whatever we already hold rather than
  /// wrongly logging the user out.
  Future<void> checkAuthStatus() async {
    try {
      _user = await _authService.refreshCurrentUser();
    } catch (e) {
      debugPrint('AuthProvider.checkAuthStatus failed: $e');
      _user = _authService.currentUser;
    }
    notifyListeners();
  }
}