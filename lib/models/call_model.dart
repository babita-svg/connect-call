import 'package:json_annotation/json_annotation.dart';

part 'call_model.g.dart';

/// Whether a call is a voice call or a video call.
enum CallType { audio, video }

/// Lifecycle state of a call.
enum CallStatus {
  calling,
  ringing,
  connected,
  ended,
  rejected,
  missed,
  busy,
}

/// A single call between two users. Immutable.
@JsonSerializable()
class CallModel {
  final String id;
  final String callerId;
  final String callerName;
  final String calleeId;
  final String calleeName;
  final CallType callType;

  /// When the call was placed / first detected.
  final DateTime startTime;

  /// When the call ended; null while still active.
  final DateTime? endTime;

  /// Call duration in seconds.
  final int duration;

  final CallStatus status;

  /// True when this call was received by the current user, false when placed.
  final bool isIncoming;

  const CallModel({
    required this.id,
    required this.callerId,
    required this.callerName,
    required this.calleeId,
    required this.calleeName,
    required this.callType,
    required this.startTime,
    this.endTime,
    this.duration = 0,
    this.status = CallStatus.calling,
    this.isIncoming = false,
  });

  /// Deserializes a [CallModel] from JSON.
  factory CallModel.fromJson(Map<String, dynamic> json) =>
      _$CallModelFromJson(json);

  /// Serializes this model to JSON.
  Map<String, dynamic> toJson() => _$CallModelToJson(this);

  /// Human-friendly duration, e.g. `4m 32s` or `1h 5m`.
  String get durationString {
    final seconds = duration < 0 ? 0 : duration;
    final d = Duration(seconds: seconds);
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);

    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  /// Creates a copy of this model with optional overridden fields.
  CallModel copyWith({
    String? id,
    String? callerId,
    String? callerName,
    String? calleeId,
    String? calleeName,
    CallType? callType,
    DateTime? startTime,
    DateTime? endTime,
    int? duration,
    CallStatus? status,
    bool? isIncoming,
  }) {
    return CallModel(
      id: id ?? this.id,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      calleeId: calleeId ?? this.calleeId,
      calleeName: calleeName ?? this.calleeName,
      callType: callType ?? this.callType,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      duration: duration ?? this.duration,
      status: status ?? this.status,
      isIncoming: isIncoming ?? this.isIncoming,
    );
  }
}