import 'dart:async';
import 'dart:developer' show log;

import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants/app_constants.dart';
import '../core/utils/call_exceptions.dart';
import '../models/call_model.dart';

/// Lifecycle state of the current call, surfaced to the UI.
enum CallState {
  idle,
  calling,
  ringing,
  connected,
  ended,
  rejected,
  missed,
  busy,
  failed,
}

/// User-facing network quality rating for the active call.
enum NetworkQuality { good, fair, poor }

/// Manages Agora RTC sessions and the corresponding Firestore call records.
class CallService {
  CallService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;
  CollectionReference get _callsRef =>
      _firestore.collection(AppConstants.callsCollection);

  // Agora engine
  late RtcEngine engine;
  bool _engineReady = false;

  // Call state
  String? _currentCallId;
  String? _currentChannel;
  String? remoteUserId;
  bool isAudioMuted = false;
  bool isVideoEnabled = false;
  bool isFrontCamera = true;
  CallState currentCallState = CallState.idle;
  Duration callDuration = Duration.zero;
  Timer? durationTimer;
  Timer? _ringingTimeout;

  /// Optional callback fired when mute/video/camera toggles occur.
  VoidCallback? onMediaToggled;

  final StreamController<CallState> _callStateStream =
      StreamController<CallState>.broadcast();
  final StreamController<Duration> _durationStream =
      StreamController<Duration>.broadcast();

  // Network quality (latest value + broadcast stream for live consumers).
  NetworkQuality _networkQuality = NetworkQuality.poor;
  final StreamController<NetworkQuality> _networkQualityStream =
      StreamController<NetworkQuality>.broadcast();

  Stream<CallState> get callStateStream => _callStateStream.stream;
  Stream<Duration> get durationStream => _durationStream.stream;
  Stream<NetworkQuality> get networkQualityStream =>
      _networkQualityStream.stream;
  NetworkQuality get networkQuality => _networkQuality;

  /// Id of the currently active call persisted to Firestore, if any.
  String? get activeCallId => _currentCallId;

  /// Fetches call records involving [userId] (as caller or callee), newest
  /// first.
  Future<List<CallModel>> fetchCallHistory(String userId) async {
    try {
      final snapshot = await _callsRef.get();
      final calls = snapshot.docs
          .map((doc) => CallModel.fromJson(doc.data()))
          .where((c) => c.callerId == userId || c.calleeId == userId)
          .toList();
      calls.sort((a, b) => b.startTime.compareTo(a.startTime));
      return calls;
    } on FirebaseException catch (e) {
      log('fetchCallHistory failed', name: 'CallService', error: e);
      throw const CallException('Could not load your call history.');
    }
  }

  /// Permanently deletes a single call record from history.
  Future<void> deleteCall(String callId) async {
    try {
      await _callsRef.doc(callId).delete();
    } on FirebaseException catch (e) {
      log('deleteCall failed', name: 'CallService', error: e);
      throw const CallException('Could not delete the call. Please try again.');
    }
  }

  /// Outgoing calls wait this long for the recipient before timing out.
  static const Duration _ringingTimeoutDuration = Duration(seconds: 60);

  // --------------------------------------------------------------------------
  // Initialization
  // --------------------------------------------------------------------------

  /// Creates the Agora engine, configures communication, and wires handlers.
  Future<void> initializeAgora(String appId, String userId) async {
    await _checkPermissions(video: false);

    try {
      engine = await createAgoraRtcEngine();
      await engine.initialize(RtcEngineContext(appId: appId));

      engine.registerEventHandler(RtcEngineEventHandler(
        onUserJoined: (connection, remoteUid, elapsed) =>
            _handleUserJoined(remoteUid),
        onUserOffline: (connection, remoteUid, reason) =>
            _handleUserOffline(),
        onError: (err, message) {
          log('Agora error $err: $message', name: 'CallService');
          _emitState(CallState.failed);
        },
        onConnectionStateChanged: _handleConnectionState,
        onNetworkQuality: _handleNetworkQuality,
      ));

      await engine.setChannelProfile(ChannelProfileType.channelProfileCommunication);
      await engine.enableVideo();
      _engineReady = true;
    } on AgoraRtcException catch (e) {
      _emitState(CallState.failed);
      log('initializeAgora failed', name: 'CallService', error: e);
      rethrow;
    }
  }

  // --------------------------------------------------------------------------
  // Outgoing calls
  // --------------------------------------------------------------------------

  Future<void> initiateAudioCall({
    required String recipientId,
    required String recipientName,
    required String currentUserId,
  }) async {
    await _checkPermissions(video: false);
    await _ensureEngine();

    _resetForNewCall();
    final callId = _saveCall(
      callerId: currentUserId,
      callerName: await _currentUserName(),
      calleeId: recipientId,
      calleeName: recipientName,
      type: CallType.audio,
    );

    await _joinChannel(callId: callId, callerId: currentUserId, calleeId: recipientId, video: false);

    _emitState(CallState.calling);
    _emitState(CallState.ringing);
    _startRingingTimeout();
  }

  Future<void> initiateVideoCall({
    required String recipientId,
    required String recipientName,
    required String currentUserId,
  }) async {
    await _checkPermissions(video: true);
    await _ensureEngine();

    _resetForNewCall();
    isVideoEnabled = true;
    final callId = _saveCall(
      callerId: currentUserId,
      callerName: await _currentUserName(),
      calleeId: recipientId,
      calleeName: recipientName,
      type: CallType.video,
    );

    await _joinChannel(callId: callId, callerId: currentUserId, calleeId: recipientId, video: true);

    _emitState(CallState.calling);
    _emitState(CallState.ringing);
    _startRingingTimeout();
  }

  // --------------------------------------------------------------------------
  // Incoming call handling
  // --------------------------------------------------------------------------

  Future<void> acceptCall(String callId, bool isVideo) async {
    await _checkPermissions(video: isVideo);
    await _ensureEngine();

    _ringingTimeout?.cancel();
    CallModel call;
    try {
      final doc = await _callsRef.doc(callId).get();
      call = CallModel.fromJson(doc.data()!);
    } catch (e) {
      log('acceptCall: could not read call', name: 'CallService', error: e);
      _emitState(CallState.failed);
      return;
    }

    await _updateStatus(callId, 'connected');

    _currentCallId = callId;
    isVideoEnabled = isVideo;
    await _joinChannel(
      callId: callId,
      callerId: call.callerId,
      calleeId: call.calleeId,
      video: isVideo,
    );

    _emitState(CallState.connected);
    startDurationTimer();
  }

  Future<void> rejectCall(String callId) async {
    await _updateStatus(callId, 'rejected');
    _emitState(CallState.rejected);
    await _leaveChannel();
    _stopRingingTimeout();
  }

  // --------------------------------------------------------------------------
  // End call
  // --------------------------------------------------------------------------

  Future<void> endCall(String callId, Duration duration) async {
    try {
      await _callsRef.doc(callId).set({
        'status': 'ended',
        'endTime': DateTime.now().toIso8601String(),
        'duration': duration.inSeconds,
      }, SetOptions(merge: true));
    } catch (e) {
      log('endCall: failed to persist', name: 'CallService', error: e);
    }

    _emitState(CallState.ended);
    stopDurationTimer();
    _stopRingingTimeout();
    await _leaveChannel();
  }

  // --------------------------------------------------------------------------
  // Media controls
  // --------------------------------------------------------------------------

  void toggleAudioMute() {
    isAudioMuted = !isAudioMuted;
    engine.muteLocalAudioStream(isAudioMuted);
    onMediaToggled?.call();
  }

  void toggleVideo() {
    isVideoEnabled = !isVideoEnabled;
    engine.muteLocalVideoStream(!isVideoEnabled);
    onMediaToggled?.call();
  }

  void switchCamera() {
    isFrontCamera = !isFrontCamera;
    engine.switchCamera();
    onMediaToggled?.call();
  }

  // --------------------------------------------------------------------------
  // Duration timer
  // --------------------------------------------------------------------------

  void startDurationTimer() {
    callDuration = Duration.zero;
    durationTimer ??= Timer.periodic(const Duration(seconds: 1), (_) {
      callDuration += const Duration(seconds: 1);
      if (!_durationStream.isClosed) _durationStream.add(callDuration);
    });
  }

  void stopDurationTimer() {
    durationTimer?.cancel();
    durationTimer = null;
    callDuration = Duration.zero;
    if (!_durationStream.isClosed) {
      _durationStream.add(Duration.zero);
    }
  }

  // --------------------------------------------------------------------------
  // Event handlers
  // --------------------------------------------------------------------------

  void _handleUserJoined(int remoteUid) {
    remoteUserId = remoteUid.toString();
    _ringingTimeout?.cancel();

    if (currentCallState != CallState.connected) {
      _emitState(CallState.connected);
      startDurationTimer();
    }
  }

  void _handleUserOffline() {
    remoteUserId = null;
    stopDurationTimer();
    if (currentCallState == CallState.connected ||
        currentCallState == CallState.ringing) {
      _emitState(CallState.ended);
    }
  }

  void _handleConnectionState(
    RtcConnection connection,
    ConnectionStateType state,
    ConnectionChangedReasonType reason,
  ) {
    // Treat interruption/disconnection of the established link as a failure.
    if (state == ConnectionStateType.connectionStateDisconnected) {
      _updateNetworkQuality(NetworkQuality.poor);
      if (currentCallState == CallState.connected ||
          currentCallState == CallState.ringing) {
        _emitState(CallState.failed);
        stopDurationTimer();
      }
    }
  }

  // --------------------------------------------------------------------------
  // Network quality monitoring
  // --------------------------------------------------------------------------

  /// Agora reports the transmit and receive quality of the established media
  /// stream on each connected remote user. We surface the *worse* of the two
  /// links so the badge reflects the current bottleneck of the call.
  void _handleNetworkQuality(
    RtcConnection connection,
    int remoteUid,
    QualityType txQuality,
    QualityType rxQuality,
  ) {
    final tx = _mapQuality(txQuality);
    final rx = _mapQuality(rxQuality);
    // Enum order is good < fair < poor, so the larger index is the worse link.
    _updateNetworkQuality(tx.index >= rx.index ? tx : rx);
  }

  NetworkQuality _mapQuality(QualityType quality) {
    switch (quality) {
      case QualityType.qualityExcellent:
      case QualityType.qualityGood:
        return NetworkQuality.good;
      case QualityType.qualityPoor:
        return NetworkQuality.fair;
      default:
        // qualityBad, qualityVBad, qualityDown, qualityDetecting, unknown, …
        return NetworkQuality.poor;
    }
  }

  void _updateNetworkQuality(NetworkQuality quality) {
    if (quality == _networkQuality) return;
    _networkQuality = quality;
    if (!_networkQualityStream.isClosed) {
      _networkQualityStream.add(quality);
    }
  }

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------

  String _saveCall({
    required String callerId,
    required String callerName,
    required String calleeId,
    required String calleeName,
    required CallType type,
  }) {
    final doc = _callsRef.doc();
    final callId = doc.id;
    _currentCallId = callId;

    final model = CallModel(
      id: callId,
      callerId: callerId,
      callerName: callerName,
      calleeId: calleeId,
      calleeName: calleeName,
      callType: type,
      startTime: DateTime.now(),
      status: CallStatus.calling,
      isIncoming: false,
    );
    doc.set(model.toJson());
    return callId;
  }

  Future<String> _currentUserName() async {
    final firebaseUser = FirebaseAuth.instance.currentUser;
    return firebaseUser?.displayName ?? '';
  }

  /// Deterministic, symmetric channel name from the two user ids.
  String _channelFor(String a, String b) {
    final sorted = [a, b]..sort();
    return 'call_${sorted[0]}_${sorted[1]}';
  }

  Future<void> _joinChannel({
    required String callId,
    required String callerId,
    required String calleeId,
    required bool video,
  }) async {
    _currentCallId = callId;
    final channel = _channelFor(callerId, calleeId);
    _currentChannel = channel;

    try {
      await engine.joinChannel(
        token: '',
        channelId: channel,
        uid: 0,
        options: ChannelMediaOptions(
          clientRoleType: ClientRoleType.clientRoleBroadcaster,
          publishCameraTrack: video,
          publishMicrophoneTrack: true,
          autoSubscribeAudio: true,
          autoSubscribeVideo: true,
        ),
      );
    } on AgoraRtcException catch (e) {
      _emitState(CallState.failed);
      throw CallException('Could not connect to the call. Please try again.');
    }
  }

  Future<void> _leaveChannel() async {
    if (!_engineReady) return;
    await engine.leaveChannel();
    _currentChannel = null;
    remoteUserId = null;
  }

  Future<void> _updateStatus(String callId, String status) async {
    try {
      await _callsRef.doc(callId).set(
        {'status': status},
        SetOptions(merge: true),
      );
    } catch (e) {
      log('updateStatus($status) failed', name: 'CallService', error: e);
      throw CallException('Could not update call status.');
    }
  }

  void _startRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = Timer(_ringingTimeoutDuration, () {
      if (currentCallState == CallState.calling ||
          currentCallState == CallState.ringing) {
        _emitState(CallState.missed);
        stopDurationTimer();
        if (_currentCallId != null) {
          _updateStatus(_currentCallId!, 'missed');
        }
        _leaveChannel();
      }
    });
  }

  void _stopRingingTimeout() {
    _ringingTimeout?.cancel();
    _ringingTimeout = null;
  }

  Future<void> _ensureEngine() async {
    if (!_engineReady) {
      throw CallException('Call engine is not initialized.');
    }
  }

  void _resetForNewCall() {
    _ringingTimeout?.cancel();
    stopDurationTimer();
    isAudioMuted = false;
    isVideoEnabled = false;
    isFrontCamera = true;
    remoteUserId = null;
    _updateNetworkQuality(NetworkQuality.poor);
  }

  Future<void> _checkPermissions({required bool video}) async {
    final microphone = Permission.microphone;
    final microphoneOk = await microphone.isGranted || await microphone.request();
    if (!microphoneOk) {
      throw const PermissionDeniedException();
    }

    if (video) {
      final camera = Permission.camera;
      final cameraOk = await camera.isGranted || await camera.request();
      if (!cameraOk) {
        throw const PermissionDeniedException();
      }
    }
  }

  void _emitState(CallState state) {
    currentCallState = state;
    if (!_callStateStream.isClosed) {
      _callStateStream.add(state);
    }
  }

  // --------------------------------------------------------------------------
  // Cleanup
  // --------------------------------------------------------------------------

  Future<void> dispose() async {
    _stopRingingTimeout();
    stopDurationTimer();
    try {
      if (_engineReady) {
        await engine.leaveChannel();
        await engine.release();
        _engineReady = false;
      }
    } catch (e) {
      log('dispose: engine release failed', name: 'CallService', error: e);
    }
    await _callStateStream.close();
    await _durationStream.close();
    await _networkQualityStream.close();
  }
}