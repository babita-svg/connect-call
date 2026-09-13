import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/user_model.dart';
import '../services/user_service.dart';

/// Exposes the contact list, search results, and the current user's profile.
class UserProvider extends ChangeNotifier {
  final UserService _userService;
  final List<StreamSubscription<UserModel?>> _subscriptions = [];

  UserProvider({UserService? userService})
      : _userService = userService ?? UserService();

  List<UserModel> _allUsers = [];
  List<UserModel> _searchResults = [];
  String _searchQuery = '';

  /// Set once the first full fetch finishes (success or failure), so the
  /// screen's first-load safety net fires at most once.
  bool _usersLoaded = false;
  UserModel? _currentUser;
  bool _isLoading = false;
  bool _profileLoaded = false;
  bool _profileLoading = false;
  String? _profileError;
  String? _error;

  /// When a search is active, allUsers is the (possibly empty) result list;
  /// otherwise it is the full contact list.
  List<UserModel> get allUsers =>
      _searchQuery.isEmpty ? _allUsers : _searchResults;

  UserModel? get currentUser => _currentUser;
  bool get isLoading => _isLoading;
  bool get hasLoadedUsers => _usersLoaded;

  /// Whether the signed-in user's profile has finished a fetch attempt
  /// (success or failure), so the profile screen's safety net fires once.
  bool get hasLoadedProfile => _profileLoaded;
  bool get isLoadingProfile => _profileLoading;
  String? get profileError => _profileError;
  String get searchQuery => _searchQuery;
  String? get error => _error;

  // --------------------------------------------------------------------------
  // Contacts
  // --------------------------------------------------------------------------

  /// Loads all users (excluding the current user).
  Future<void> fetchAllUsers() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _allUsers = await _userService.getAllUsers();
      if (_searchResults.isNotEmpty) {
        _searchResults = [];
      }
    } catch (e) {
      _error = 'Could not load contacts. Please try again.';
    } finally {
      _usersLoaded = true;
      _searchQuery = '';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Searches users by (case-insensitive) name. Empty query clears results.
  Future<void> searchUsers(String query) async {
    final trimmed = query.trim();
    _searchQuery = trimmed;
    if (trimmed.isEmpty) {
      _searchResults = [];
      notifyListeners();
      return;
    }

    try {
      _searchResults = await _userService.searchUsers(trimmed);
    } catch (e) {
      _error = 'Search failed. Please try again.';
    }
    notifyListeners();
  }

  /// Restores the full contact list.
  Future<void> clearSearch() => searchUsers('');

  // --------------------------------------------------------------------------
  // Current user
  // --------------------------------------------------------------------------

  /// Loads the signed-in user's profile.
  ///
  /// The loaded flag flips in `finally` so a failed first fetch does not
  /// re-trigger the profile screen's single-shot safety net.
  Future<void> fetchCurrentUserProfile(String uid) async {
    _profileLoading = true;
    _profileError = null;
    notifyListeners();
    try {
      _currentUser = await _userService.getUser(uid);
    } catch (e) {
      debugPrint('UserProvider.fetchCurrentUserProfile failed: $e');
      _profileError = 'Could not load your profile.';
    } finally {
      _profileLoading = false;
      _profileLoaded = true;
      notifyListeners();
    }
  }

  /// Updates editable profile fields, then refreshes the stored profile.
  ///
  /// Returns `true` when the update and refresh succeeded; `false` on failure
  /// so the edit screen can stay open and report the error.
  Future<bool> updateUserProfile(
    String uid, {
    String? name,
    String? phone,
    String? photoUrl,
  }) async {
    try {
      await _userService.updateUserProfile(
        uid,
        name: name,
        phone: phone,
        photoUrl: photoUrl,
      );
      await fetchCurrentUserProfile(uid);
      return true;
    } catch (e) {
      debugPrint('UserProvider.updateUserProfile failed: $e');
      _profileError = 'Could not update your profile. Please try again.';
      return false;
    }
  }

  /// Clears the stored error messages.
  void clearError() {
    _error = null;
    _profileError = null;
    notifyListeners();
  }

  /// Resets state so a freshly signed-in user starts clean.
  void reset() {
    _disposePresence();
    _allUsers = [];
    _searchResults = [];
    _searchQuery = '';
    _currentUser = null;
    _profileLoaded = false;
    _profileLoading = false;
    _profileError = null;
    _isLoading = false;
    _usersLoaded = false;
    _error = null;
    notifyListeners();
  }

  /// Updates the signed-in user's presence on Firestore — call it with
  /// `true` when the app opens/returns and `false` when it closes/backgrounds.
  Future<void> updateOnlineStatus(String uid, bool online) {
    return _userService.updateOnlineStatus(uid, online);
  }

  // --------------------------------------------------------------------------
  // Realtime presence (optional)
  // --------------------------------------------------------------------------

  /// Subscribes to presence changes for each visible user and replaces their
  /// entry in [_allUsers] as `isOnline`/`lastSeen` change.
  ///
  /// Call this after [fetchAllUsers]; call [disposePresence] when leaving the
  /// contacts screen to stop listening.
  void listenToPresence() {
    _disposePresence();
    for (final user in _allUsers) {
      final sub = _userService.getOnlineStatus(user.uid).listen((isOnline) {
        if (!_allUsers.any((u) => u.uid == user.uid)) return;
        _allUsers = [
          for (final u in _allUsers)
            if (u.uid == user.uid) u.copyWith(isOnline: isOnline) else u,
        ];
        notifyListeners();
      });
      _subscriptions.add(sub);
    }
  }

  /// Stops all presence subscriptions.
  void disposePresence() => _disposePresence();

  void _disposePresence() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }

  @override
  void dispose() {
    _disposePresence();
    super.dispose();
  }
}