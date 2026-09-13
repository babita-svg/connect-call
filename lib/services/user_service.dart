import 'dart:developer' show log;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/firestore_exceptions.dart';
import '../models/user_model.dart';

/// CRUD and query operations against the `users` collection.
class UserService {
  final FirebaseFirestore _firestore;

  UserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference get _usersRef =>
      _firestore.collection(AppConstants.usersCollection);

  /// Id of the signed-in user, used to exclude them from contact lists.
  String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  // --------------------------------------------------------------------------
  // Create
  // --------------------------------------------------------------------------

  /// Creates a new user document in `users`.
  ///
  /// Written inside a single [WriteBatch] so additional related writes
  /// (e.g. a default contact doc) can be added atomically later.
  Future<void> createUser({
    required String uid,
    required String name,
    required String email,
  }) async {
    final batch = _firestore.batch();
    final now = DateTime.now();

    batch.set(_usersRef.doc(uid), {
      'uid': uid,
      'name': name.trim(),
      'email': email.trim(),
      'photoUrl': '',
      'isOnline': false,
      'lastSeen': now.toIso8601String(),
      'createdAt': now.toIso8601String(),
    });

    try {
      await batch.commit();
    } catch (e) {
      _logFailure('createUser', e);
      throw const FirestoreException('Could not create your account. Please try again.');
    }
  }

  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// Fetches a user document by [uid].
  Future<UserModel> getUser(String uid) async {
    try {
      final doc = await _usersRef.doc(uid).get();
      if (!doc.exists) {
        throw const DocumentNotFoundException('User');
      }
      final data = doc.data();
      if (data == null) {
        throw const DocumentNotFoundException('User');
      }
      return UserModel.fromJson(data);
    } catch (e) {
      _logFailure('getUser', e);
      rethrow;
    }
  }

  /// Fetches all users except the signed-in user, online-first then name.
  Future<List<UserModel>> getAllUsers() async {
    try {
      final snapshot = await _usersRef.get();
      final currentUid = _currentUid;

      final users = snapshot.docs
          .map((doc) => UserModel.fromJson(doc.data()))
          .where((user) => user.uid != currentUid)
          .toList();

      users.sort(_compareUsers);
      return users;
    } on FirebaseException catch (e) {
      _logFailure('getAllUsers', e);
      throw const FirestoreException('Could not load contacts. Please try again.');
    } catch (e) {
      _logFailure('getAllUsers', e);
      rethrow;
    }
  }

  /// Case-insensitive name search over all users (excluding the current user).
  Future<List<UserModel>> searchUsers(String query) async {
    final term = query.trim().toLowerCase();
    if (term.isEmpty) return const [];

    try {
      final snapshot = await _usersRef.get();
      final currentUid = _currentUid;

      final matches = snapshot.docs
          .map((doc) => UserModel.fromJson(doc.data()))
          .where((user) => user.uid != currentUid)
          .where((user) => user.name.toLowerCase().contains(term))
          .toList();

      matches.sort(_compareUsers);
      return matches;
    } catch (e) {
      _logFailure('searchUsers', e);
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // Update
  // --------------------------------------------------------------------------

  /// Updates a user's presence. Pass [isOnline] when the app opens/closes.
  Future<void> updateOnlineStatus(String uid, bool isOnline) async {
    try {
      await _usersRef.doc(uid).set({
        'isOnline': isOnline,
        'lastSeen': DateTime.now().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (e) {
      _logFailure('updateOnlineStatus', e);
      throw const FirestoreException('Could not update your status. Please try again.');
    }
  }

  /// Updates editable profile fields: [name], [phone] and/or [photoUrl].
  Future<void> updateUserProfile(
    String uid, {
    String? name,
    String? phone,
    String? photoUrl,
  }) async {
    try {
      final update = <String, dynamic>{};
      if (name != null) update['name'] = name.trim();
      if (phone != null) update['phone'] = phone.trim();
      if (photoUrl != null) update['photoUrl'] = photoUrl;
      if (update.isEmpty) return;

      await _usersRef.doc(uid).set(update, SetOptions(merge: true));
    } catch (e) {
      _logFailure('updateUserProfile', e);
      throw const FirestoreException('Could not update your profile. Please try again.');
    }
  }

  // --------------------------------------------------------------------------
  // Realtime presence
  // --------------------------------------------------------------------------

  /// Realtime stream of a user's online status.
  Stream<bool> getOnlineStatus(String uid) {
    return _usersRef
        .doc(uid)
        .snapshots()
        .handleError((Object e) {
          _logFailure('getOnlineStatus', e);
          throw const FirestoreException('Could not load presence.');
        })
        .map((doc) => doc.data()?['isOnline'] as bool? ?? false);
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------

  /// Sorts online users first, then alphabetically by name (case-insensitive).
  int _compareUsers(UserModel a, UserModel b) {
    if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  }

  void _logFailure(String method, Object e) {
    log('UserService.$method failed', name: 'UserService', error: e);
  }
}