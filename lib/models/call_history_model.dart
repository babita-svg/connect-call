import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

import 'call_model.dart';

part 'call_history_model.g.dart';

/// A [CallModel] presented in the call-history list. Inherits all call fields
/// and adds presentation helpers. Immutable.
@JsonSerializable()
class CallHistoryModel extends CallModel {
  const CallHistoryModel({
    required super.id,
    required super.callerId,
    required super.callerName,
    required super.calleeId,
    required super.calleeName,
    required super.callType,
    required super.startTime,
    super.endTime,
    super.duration,
    super.status,
    super.isIncoming,
  });

  /// Deserializes a [CallHistoryModel] from JSON.
  factory CallHistoryModel.fromJson(Map<String, dynamic> json) =>
      _$CallHistoryModelFromJson(json);

  /// Wraps a plain [CallModel] (from history queries) to expose the
  /// presentation getters ([icon], [isMissed], [durationString]).
  factory CallHistoryModel.fromCall(CallModel call) => CallHistoryModel(
        id: call.id,
        callerId: call.callerId,
        callerName: call.callerName,
        calleeId: call.calleeId,
        calleeName: call.calleeName,
        callType: call.callType,
        startTime: call.startTime,
        endTime: call.endTime,
        duration: call.duration,
        status: call.status,
        isIncoming: call.isIncoming,
      );

  /// Serializes this model to JSON.
  @override
  Map<String, dynamic> toJson() => _$CallHistoryModelToJson(this);

  /// True when the call was never answered.
  bool get isMissed => status == CallStatus.missed;

  /// Icon representing the call's outcome/direction.
  IconData get icon {
    switch (status) {
      case CallStatus.calling:
      case CallStatus.ringing:
        return Icons.call;
      case CallStatus.connected:
        return isIncoming ? Icons.call_received : Icons.call_made;
      case CallStatus.ended:
      case CallStatus.rejected:
        return Icons.call_end;
      case CallStatus.missed:
        return Icons.call_missed;
      case CallStatus.busy:
        return Icons.do_not_disturb_on;
    }
  }

  /// Creates a copy of this model with optional overridden fields.
  @override
  CallHistoryModel copyWith({
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
    return CallHistoryModel(
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