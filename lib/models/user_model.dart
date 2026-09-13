import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

/// A registered user of the app. Immutable.
@JsonSerializable()
class UserModel {
  final String uid;
  final String name;
  final String email;
  final String? phone;
  final String? photoUrl;
  final bool isOnline;

  /// Last time the user was seen online.
  final DateTime lastSeen;

  /// When the account was created.
  final DateTime createdAt;

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.phone,
    this.photoUrl,
    this.isOnline = false,
    required this.lastSeen,
    required this.createdAt,
  });

  /// Deserializes a [UserModel] from JSON.
  factory UserModel.fromJson(Map<String, dynamic> json) =>
      _$UserModelFromJson(json);

  /// Serializes this model to JSON.
  Map<String, dynamic> toJson() => _$UserModelToJson(this);

  /// Creates a copy of this model with optional overridden fields.
  ///
  /// Passing `null` to [photoUrl] keeps the existing value unchanged.
  UserModel copyWith({
    String? uid,
    String? name,
    String? email,
    String? phone,
    String? photoUrl,
    bool? isOnline,
    DateTime? lastSeen,
    DateTime? createdAt,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      photoUrl: photoUrl ?? this.photoUrl,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel &&
        other.uid == uid &&
        other.name == name &&
        other.email == email &&
        other.phone == phone &&
        other.photoUrl == photoUrl &&
        other.isOnline == isOnline &&
        other.lastSeen == lastSeen &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode =>
      Object.hash(uid, name, email, phone, photoUrl, isOnline, lastSeen, createdAt);
}