import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/call_model.dart';
import '../services/call_service.dart';

/// Exposes the active call, its state, media controls, and call history.
class CallProvider extends ChangeNotifier {
  final CallService _callService;

  CallProvider({CallService? callService})
      : _callService = callService ?? CallService();

  StreamSubscription<CallState>? _callStateSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<NetworkQuality>? _networkQualitySub;

  CallModel? _currentCall;
  CallState _callState = CallState.idle;
  NetworkQuality _networkQuality = NetworkQuality.poor;
  bool _isAudioMuted = false;
  bool _isVideoEnabled = false;
  bool _isFrontCamera = true;
  Duration _callDuration = Duration.zero;
  List<CallModel> _callHistory = [];
  bool _isLoadingHistory = false;

  /// Set once a history fetch has succeeded (even with zero results) so the
  /// screen can skip the first-load safety net on later rebuilds.
  bool _historyLoaded = false;
  String? _fetchError;

  CallModel? get currentCall => _currentCall;
  CallState get callState => _callState;
  NetworkQuality get networkQuality => _networkQuality;

  /// The underlying [CallService] — exposed so call screens can render
  /// video and access the engine directly.
  CallService get callService => _callService;
  bool get isAudioMuted => _isAudioMuted;
  bool get isVideoEnabled => _isVideoEnabled;
  bool get isFrontCamera => _isFrontCamera;
  Duration get callDuration => _callDuration;
  String get durationString =>
      '${_callDuration.inMinutes}:${(_callDuration.inSeconds % 60).toString().padLeft(2, '0')}';
  List<CallModel> get callHistory => _callHistory;
  bool get isLoadingHistory => _isLoadingHistory;
  bool get hasLoadedHistory => _historyLoaded;
  String? get fetchError => _fetchError;

  /// Subscribes to the CallService's state and duration streams.
  void init() {
    _callStateSub = _callService.callStateStream.listen((state) {
      _callState = state;
      notifyListeners();
    });
    _durationSub = _callService.durationStream.listen((duration) {
      _callDuration = duration;
      notifyListeners();
    });
    _networkQualitySub = _callService.networkQualityStream.listen((quality) {
      _networkQuality = quality;
      notifyListeners();
    });
  }

  // --------------------------------------------------------------------------
  // Initiating calls
  // --------------------------------------------------------------------------

  Future<void> initiateAudioCall({
    required String recipientId,
    required String recipientName,
    required String currentUserId,
    required String currentUserName,
  }) async {
    _callState = CallState.calling;
    _currentCall = _makeCall(
      recipientId: recipientId,
      recipientName: recipientName,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      type: CallType.audio,
    );
    notifyListeners();

    await _callService.initiateAudioCall(
      recipientId: recipientId,
      recipientName: recipientName,
      currentUserId: currentUserId,
    );
    _syncCallId();
  }

  Future<void> initiateVideoCall({
    required String recipientId,
    required String recipientName,
    required String currentUserId,
    required String currentUserName,
  }) async {
    _isVideoEnabled = true;
    _callState = CallState.calling;
    _currentCall = _makeCall(
      recipientId: recipientId,
      recipientName: recipientName,
      currentUserId: currentUserId,
      currentUserName: currentUserName,
      type: CallType.video,
    );
    notifyListeners();

    await _callService.initiateVideoCall(
      recipientId: recipientId,
      recipientName: recipientName,
      currentUserId: currentUserId,
    );
    _syncCallId();
  }

  // --------------------------------------------------------------------------
  // Incoming calls
  // --------------------------------------------------------------------------

  Future<void> acceptCall(String callId, bool isVideo) async {
    _isVideoEnabled = isVideo;
    await _callService.acceptCall(callId, isVideo);
    _callState = CallState.connected;
    notifyListeners();
  }

  Future<void> rejectCall(String callId) async {
    await _callService.rejectCall(callId);
    _callState = CallState.rejected;
    notifyListeners();

    _clearCurrentCallAfterDelay();
  }

  // --------------------------------------------------------------------------
  // Ending a call
  // --------------------------------------------------------------------------

  Future<void> endCall() async {
    final call = _currentCall;
    if (call != null) {
      await _callService.endCall(call.id, _callDuration);
      _callHistory.insert(0, call);
    }
    _callState = CallState.ended;
    _resetCallFields();
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Media controls
  // --------------------------------------------------------------------------

  void toggleAudio() {
    _isAudioMuted = !_isAudioMuted;
    _callService.toggleAudioMute();
    notifyListeners();
  }

  void toggleVideo() {
    _isVideoEnabled = !_isVideoEnabled;
    _callService.toggleVideo();
    notifyListeners();
  }

  void switchCamera() {
    _isFrontCamera = !_isFrontCamera;
    _callService.switchCamera();
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // History & state
  // --------------------------------------------------------------------------

  Future<void> fetchCallHistory(String userId) async {
    _isLoadingHistory = true;
    _fetchError = null;
    notifyListeners();
    try {
      _callHistory = await _callService.fetchCallHistory(userId);
    } catch (e) {
      debugPrint('CallProvider.fetchCallHistory failed: $e');
      _fetchError = 'Could not load call history.';
    }
    _historyLoaded = true;
    _isLoadingHistory = false;
    notifyListeners();
  }

  /// Removes a call from the local history immediately, then best-effort
  /// deletes it from Firestore.
  Future<void> deleteCallHistoryItem(String callId) async {
    final index = _callHistory.indexWhere((c) => c.id == callId);
    if (index == -1) return;
    _callHistory.removeAt(index);
    notifyListeners();
    try {
      await _callService.deleteCall(callId);
    } catch (e) {
      debugPrint('CallProvider.deleteCallHistoryItem failed: $e');
    }
  }

  void clearCallState() {
    _resetCallFields();
    notifyListeners();
  }

  /// Resets call state and history so a freshly signed-in user starts clean.
  void reset() {
    _callStateSub?.cancel();
    _durationSub?.cancel();
    _networkQualitySub?.cancel();
    _callStateSub = null;
    _durationSub = null;
    _networkQualitySub = null;
    _currentCall = null;
    _callState = CallState.idle;
    _networkQuality = NetworkQuality.poor;
    _isAudioMuted = false;
    _isVideoEnabled = false;
    _isFrontCamera = true;
    _callDuration = Duration.zero;
    _callHistory = [];
    _isLoadingHistory = false;
    _historyLoaded = false;
    _fetchError = null;
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Internals
  // --------------------------------------------------------------------------

  CallModel _makeCall({
    required String recipientId,
    required String recipientName,
    required String currentUserId,
    required String currentUserName,
    required CallType type,
  }) {
    return CallModel(
      id: 'pending_${DateTime.now().millisecondsSinceEpoch}',
      callerId: currentUserId,
      callerName: currentUserName,
      calleeId: recipientId,
      calleeName: recipientName,
      callType: type,
      startTime: DateTime.now(),
      status: CallStatus.calling,
      isIncoming: false,
    );
  }

  /// Points [_currentCall] at the real Firestore id once [CallService] has
  /// created the document.
  void _syncCallId() {
    final id = _callService.activeCallId;
    if (id != null && _currentCall != null) {
      _currentCall = _currentCall!.copyWith(id: id);
    }
  }

  void _clearCurrentCallAfterDelay() {
    Future.delayed(const Duration(seconds: 1), () {
      _currentCall = null;
      notifyListeners();
    });
  }

  void _resetCallFields() {
    _currentCall = null;
    _callState = CallState.idle;
    _networkQuality = NetworkQuality.poor;
    _isAudioMuted = false;
    _isVideoEnabled = false;
    _isFrontCamera = true;
    _callDuration = Duration.zero;
  }

  @override
  void dispose() {
    _callStateSub?.cancel();
    _durationSub?.cancel();
    _networkQualitySub?.cancel();
    super.dispose();
  }
}