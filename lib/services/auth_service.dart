import 'dart:developer' show log;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/auth_exceptions.dart';
import '../models/user_model.dart';

/// Wraps Firebase Authentication (email/password) with Firestore persistence
/// and a friendly, domain-specific exception surface for the UI.
class AuthService {
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  /// Cached view of the signed-in user's Firestore profile.
  UserModel? _cachedUser;

  /// Last user-friendly error message (for provider screen feedback).
  String? _error;
  String? get error => _error;

  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final RegExp _emailRegExp = RegExp(r'^[\w\.-]+@[\w-]+(\.[\w-]+)+$');

  // --------------------------------------------------------------------------
  // Auth state
  // --------------------------------------------------------------------------

  /// Stream of the underlying Firebase authentication state.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// The signed-in user's Firestore profile, or null when not authenticated.
  ///
  /// This is a synchronous getter, so it returns the last-cached profile.
  /// Use [refreshCurrentUser] to re-read Firestore for fresh data.
  UserModel? get currentUser {
    if (_auth.currentUser == null) return null;
    return _cachedUser;
  }

  /// Re-fetches the current user's profile from Firestore.
  Future<UserModel?> refreshCurrentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;
    _cachedUser = await _fetchUserModel(firebaseUser.uid);
    return _cachedUser;
  }

  // --------------------------------------------------------------------------
  // Sign up
  // --------------------------------------------------------------------------

  /// Creates an account, persists the profile to Firestore, and signs in.
  Future<UserModel?> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    _clearError();

    final trimmedEmail = email.trim();
    final trimmedName = name.trim();

    if (!_emailRegExp.hasMatch(trimmedEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.length < 6) {
      throw const WeakPasswordException();
    }
    if (trimmedName.isEmpty) {
      throw const AuthException('Please enter your name.');
    }

    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );
      final firebaseUser = credential.user;

      // Completed sign-up should always yield a user, but guard anyway.
      if (firebaseUser == null) {
        throw const GenericAuthException();
      }

      final now = DateTime.now();
      final model = UserModel(
        uid: firebaseUser.uid,
        name: trimmedName,
        email: trimmedEmail,
        photoUrl: null,
        isOnline: true,
        lastSeen: now,
        createdAt: now,
      );

      await _firestore
          .collection(AppConstants.usersCollection)
          .doc(firebaseUser.uid)
          .set(model.toJson());

      _cachedUser = model;
      return model;
    } on FirebaseAuthException catch (e) {
      _logFailure('signUp', e);
      throw _mapAuthException(e);
    } catch (e) {
      _logFailure('signUp', e);
      throw const GenericAuthException();
    }
  }

  // --------------------------------------------------------------------------
  // Sign in
  // --------------------------------------------------------------------------

  /// Signs in an existing user and returns their Firestore profile.
  Future<UserModel?> signIn({
    required String email,
    required String password,
  }) async {
    _clearError();

    final trimmedEmail = email.trim();
    if (!_emailRegExp.hasMatch(trimmedEmail)) {
      throw const AuthException('Please enter a valid email address.');
    }
    if (password.isEmpty) {
      throw const AuthException('Please enter your password.');
    }

    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: trimmedEmail,
        password: password,
      );
      final firebaseUser = credential.user;
      if (firebaseUser == null) {
        throw const GenericAuthException();
      }

      var model = await _fetchUserModel(firebaseUser.uid);
      // Reconcile a missing Firestore profile (e.g. pre-existing auth record).
      model ??= UserModel(
        uid: firebaseUser.uid,
        name: firebaseUser.displayName ?? 'New User',
        email: firebaseUser.email ?? trimmedEmail,
        photoUrl: firebaseUser.photoURL,
        isOnline: true,
        lastSeen: DateTime.now(),
        createdAt: DateTime.now(),
      );

      _cachedUser = model;
      return model;
    } on FirebaseAuthException catch (e) {
      _logFailure('signIn', e);
      throw _mapAuthException(e);
    } catch (e) {
      _logFailure('signIn', e);
      throw const GenericAuthException();
    }
  }

  // --------------------------------------------------------------------------
  // Logout
  // --------------------------------------------------------------------------

  /// Signs the current user out of Firebase.
  Future<void> logout() async {
    _cachedUser = null;
    await _auth.signOut();
  }

  /// Clears the stored user-facing error message.
  void clearError() => _clearError();

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------

  Future<UserModel?> _fetchUserModel(String uid) async {
    final doc = await _firestore
        .collection(AppConstants.usersCollection)
        .doc(uid)
        .get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return UserModel.fromJson(data);
  }

  /// Maps a Firebase [FirebaseAuthException] to a friendly domain exception.
  AuthException _mapAuthException(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return const EmailAlreadyExistsException();
      case 'weak-password':
        return const WeakPasswordException();
      case 'user-not-found':
        return const UserNotFoundException();
      case 'wrong-password':
      // Newer Firebase reports a combined 'invalid-credential' for both
      // a wrong password and a non-existent user.
      case 'invalid-credential':
        return const WrongPasswordException();
      case 'invalid-email':
        return const AuthException('Please enter a valid email address.');
      default:
        return const GenericAuthException();
    }
  }

  void _clearError() => _error = null;

  /// Records a user-friendly [AuthException] message on [_error] and logs the
  /// underlying exception to the console for debugging.
  void _logFailure(String method, Object e) {
    if (e is AuthException) {
      _error = e.message;
    }
    log(
      'AuthService.$method failed',
      name: 'AuthService',
      time: DateTime.now(),
      error: e,
    );
  }
}